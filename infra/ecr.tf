resource "aws_ecr_repository" "execucao" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  # Permite destroy com imagens no repositorio.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = local.name_prefix
  }
}

resource "aws_ecr_lifecycle_policy" "execucao" {
  repository = aws_ecr_repository.execucao.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as 10 imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
