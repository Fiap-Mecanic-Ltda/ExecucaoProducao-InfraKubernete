variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "mechanicltda"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "service_name" {
  type        = string
  description = "Sufixo do microsservico nos nomes dos recursos e no prefixo do SSM."
  default     = "execucao"
}

# Cluster compartilhado: VPC, nos k3s, ALB interno e provider OIDC vem do
# repositorio InfraKubernete, lido via terraform_remote_state (data.tf).

variable "kubernetes_state_bucket" {
  type        = string
  description = "Bucket S3 com o state do stack de infraestrutura de Kubernetes."
  default     = "mechanicltda-terraform-state-788516091173"
}

variable "kubernetes_state_key" {
  type        = string
  description = "Chave do state do stack de infraestrutura de Kubernetes dentro do bucket."
  default     = "prod/terraform.tfstate"
}

# Tabelas DynamoDB: a policy de acesso vem do ExecucaoProducao-InfraSGBD, lido via
# terraform_remote_state, e e anexada as roles dos nos do k3s (dynamodb.tf).

variable "sgbd_state_key" {
  type        = string
  description = "Chave do state do ExecucaoProducao-InfraSGBD dentro do bucket."
  default     = "prod/execucao-sgbd/terraform.tfstate"
}

# ECR e Kubernetes

variable "ecr_repository_name" {
  type    = string
  default = "mechanicltda-execucao"
}

variable "node_port" {
  type        = number
  description = "NodePort do Service da Execucao. Precisa estar liberado no SG dos nos (microsservicos_node_ports no InfraKubernete)."
  default     = 8082
}

# ALB

variable "rotear_trafego_alb" {
  type        = bool
  description = <<-EOT
    Cria a regra no listener do ALB interno que manda as rotas de execucao, estoque
    e servicos para este servico. Fica false ate a virada (Etapa 9): enquanto isso,
    o monolito continua atendendo /api/estoque e /api/servicos-oficina e o target
    group existe sem trafego.
  EOT
  default     = false
}

variable "alb_rule_priority" {
  type        = number
  description = "Prioridade da regra no listener (menor vence). A acao padrao do listener continua sendo o monolito. A do OS Service e 100; cada regra precisa de uma prioridade propria."
  default     = 110
}

variable "caminhos_roteados" {
  type        = list(string)
  description = "Path patterns do ALB atendidos pela Execucao (o ALB diferencia maiusculas; no maximo 5). As rotas do monolito e do servico sao em minusculas."
  default     = ["/api/execucao*", "/api/estoque*", "/api/servicos-oficina*"]
}

# GitHub OIDC

variable "github_repositories" {
  type        = map(number)
  description = "Repositorios GitHub (owner/repo => ID numerico) autorizados a assumir a role de CI/CD da Execucao."
  default = {
    "Fiap-Mecanic-Ltda/ExecucaoProducao-service"        = 1451616552
    "Fiap-Mecanic-Ltda/ExecucaoProducao-InfraKubernete" = 1451617083
  }
}

variable "github_owner_id" {
  type        = number
  description = "ID numerico da organizacao (https://api.github.com/orgs/Fiap-Mecanic-Ltda)."
  default     = 273456374
}

variable "github_branches" {
  type        = list(string)
  description = "Branches que podem assumir a role (publicacao e deploy so rodam na main)."
  default     = ["main"]
}
