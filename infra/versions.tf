terraform {
  # Backend s3 usa locking nativo (use_lockfile), sem DynamoDB.
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Mesmo bucket dos demais stacks, chave propria: a infra da Execucao pode
  # ser aplicada/destruida sem tocar no cluster compartilhado.
  backend "s3" {
    bucket       = "mechanicltda-terraform-state-788516091173"
    key          = "prod/execucao-k8s/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project = var.project_name
      Service = var.service_name
    }
  }
}
