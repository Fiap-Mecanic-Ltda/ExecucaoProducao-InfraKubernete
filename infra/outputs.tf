output "ecr_repository_url" {
  value = aws_ecr_repository.execucao.repository_url
}

output "github_actions_role_arn" {
  description = "Vai no secret AWS_ROLE_ARN do ExecucaoProducao-service e deste repositorio."
  value       = aws_iam_role.github_actions.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.execucao.arn
}

output "trafego_roteado" {
  description = "true quando o ALB ja manda as rotas da Execucao para este servico."
  value       = var.rotear_trafego_alb
}

output "ssm_path_prefix" {
  value = local.ssm_path_prefix
}

output "dynamodb_policy_roles" {
  description = "Roles dos nos que receberam a policy das tabelas."
  value       = [for anexo in aws_iam_role_policy_attachment.dynamodb_nos : anexo.role]
}
