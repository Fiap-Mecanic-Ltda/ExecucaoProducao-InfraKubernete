# Role de CI/CD da Execucao, assumida via OIDC pelos workflows do
# ExecucaoProducao-service (push da imagem) e deste repositorio (deploy). Usa o
# provider OIDC que ja existe na conta (criado pelo InfraKubernete) e tem so as
# permissoes do servico: o ECR dele, o prefixo SSM dele e o SSM Run Command no
# server k3s.

locals {
  # Com immutable subject claims ligado na organizacao, o sub vem como
  # "owner@<owner_id>/repo@<repo_id>". As duas formas ficam liberadas, como na
  # role do InfraKubernete.
  github_oidc_repo_subjects = flatten([
    for repo, repo_id in var.github_repositories : [
      repo,
      format(
        "%s@%s/%s@%s",
        split("/", repo)[0], var.github_owner_id,
        split("/", repo)[1], repo_id,
      ),
    ]
  ])

  github_oidc_subjects = flatten([
    for repo in local.github_oidc_repo_subjects : concat(
      [for branch in var.github_branches : "repo:${repo}:ref:refs/heads/${branch}"],
      ["repo:${repo}:environment:production"]
    )
  ])
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.cluster.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_oidc_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

data "aws_iam_policy_document" "github_actions" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      # O deploy descobre a tag da ultima imagem publicada (os Deployments usam
      # imagePullPolicy IfNotPresent, entao "latest" nao serve).
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = [aws_ecr_repository.execucao.arn]
  }

  # Run Command so no server k3s (pela tag Name), onde o kubectl roda. A tag em
  # vez do id: o server pode ser recriado no InfraKubernete.
  statement {
    sid       = "SendCommandServer"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/Name"
      values   = [local.server_name_tag]
    }
  }

  statement {
    sid       = "SendCommandDocument"
    effect    = "Allow"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript"]
  }

  statement {
    sid    = "ReadCommandResult"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ec2:DescribeInstances",
    ]
    resources = ["*"]
  }

  # Parametros que o deploy junta no cluster: o prefixo do servico (tabelas),
  # a chave JWT compartilhada (os tokens sao emitidos pelo monolito e pela
  # Lambda), a license key do New Relic e as credenciais do RabbitMQ.
  statement {
    sid    = "SsmReadParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_prefix}/*",
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_prefix_compartilhado}/jwt-secret-key",
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_prefix_compartilhado}/newrelic-license-key",
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${local.ssm_path_prefix_compartilhado}/mensageria/*",
    ]
  }

  statement {
    sid       = "SsmKmsDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]
  }

  # Manifestos renderizados vao para o S3 e a instancia baixa de la (a role da
  # EC2 ja le deploy/*): inline no SSM o comando travava acima de ~10KB.
  statement {
    sid       = "DeployManifestWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/deploy/${var.service_name}/*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "${local.name_prefix}-github-actions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions.json
}
