# Entrada da Execucao: API Gateway -> VPC Link -> ALB interno (compartilhado)
# -> NodePort 8082 de qualquer no do k3s. O ALB e o listener sao do
# InfraKubernete; aqui ficam so o target group e a regra de roteamento.

resource "aws_lb_target_group" "execucao" {
  name        = "${local.name_prefix}-tg"
  port        = var.node_port
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = local.cluster.vpc_id

  # /health e anonimo na Execucao. Como o alvo e o NodePort, qualquer no
  # saudavel atende, esteja o pod onde estiver.
  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

# O server do k3s tambem roda pods. Se ele for recriado no InfraKubernete, um
# novo apply aqui atualiza o alvo (o id vem do state de la).
resource "aws_lb_target_group_attachment" "server" {
  target_group_arn = aws_lb_target_group.execucao.arn
  target_id        = local.cluster.ec2_instance_id
  port             = var.node_port
}

# Workers do ASG compartilhado. O ASG la tem ignore_changes em
# target_group_arns para que o apply de um stack nao desfaca o do outro.
resource "aws_autoscaling_attachment" "workers" {
  autoscaling_group_name = local.cluster.worker_asg_name
  lb_target_group_arn    = aws_lb_target_group.execucao.arn
}

# Desligada ate a virada: com ela, as rotas de estoque e servicos deixam de ir para o monolito
# (acao padrao do listener) e passam a vir para ca. O API Gateway nao muda -
# ele ja manda ANY /api/{proxy+} para o listener.
resource "aws_lb_listener_rule" "execucao" {
  count = var.rotear_trafego_alb ? 1 : 0

  listener_arn = local.cluster.alb_listener_arn
  priority     = var.alb_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.execucao.arn
  }

  condition {
    path_pattern {
      values = var.caminhos_roteados
    }
  }

  tags = {
    Name = "${local.name_prefix}-rota"
  }
}
