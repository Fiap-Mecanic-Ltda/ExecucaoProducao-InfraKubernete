# Acesso dos pods da Execucao as tabelas DynamoDB. A API usa a cadeia padrao de credenciais do
# SDK, que no k3s chega na role da instancia pelo IMDSv2 (AL2023 vem com hop limit 2, o que
# basta para um pod). Por isso a policy vai nas roles do server e dos workers: o pod pode
# rodar em qualquer no.
#
# A policy (tabelas execucao-* e indices) e criada pelo ExecucaoProducao-InfraSGBD; este stack so
# a anexa. As roles sao do InfraKubernete, mas um attachment nao altera o recurso de la.
resource "aws_iam_role_policy_attachment" "dynamodb_nos" {
  for_each = toset(local.node_role_names)

  role       = each.value
  policy_arn = data.terraform_remote_state.sgbd.outputs.policy_arn
}
