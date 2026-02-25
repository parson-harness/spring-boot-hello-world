resource "aws_lb" "main" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "${var.app_name}-alb"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "prod" {
  name     = "${var.app_name}-prod-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "${var.app_name}-prod-tg"
    Environment = var.environment
  }
}

resource "aws_lb_target_group" "stage" {
  name     = "${var.app_name}-stage-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = {
    Name        = "${var.app_name}-stage-tg"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.prod.arn
        weight = 100
      }

      target_group {
        arn    = aws_lb_target_group.stage.arn
        weight = 0
      }
    }
  }

  tags = {
    Name        = "${var.app_name}-prod-listener"
    Environment = var.environment
  }
}

resource "aws_lb_listener_rule" "weighted" {
  listener_arn = aws_lb_listener.prod.arn
  priority     = 100

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.prod.arn
        weight = 100
      }

      target_group {
        arn    = aws_lb_target_group.stage.arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = {
    Name        = "${var.app_name}-weighted-rule"
    Environment = var.environment
  }
}
