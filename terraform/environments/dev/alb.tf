########################################
# Phase 2c: ALB + security groups
#
# The security model (the important part):
#  - ALB SG: allows HTTP :80 from the internet. The ALB is meant to be public.
#  - TASK SG: allows :8080 ONLY from the ALB SG (source = security group, not
#    a CIDR). So even though Fargate tasks have public IPs in public subnets,
#    nothing can reach them directly -- traffic must pass through the ALB.
#    This is the compensating control for running without private subnets/NAT.
#
#  HTTP only for this demo. Production would terminate HTTPS on the ALB with an
#  ACM cert and redirect :80 -> :443. Noted as future work.
########################################

# ---- ALB security group: public HTTP in ----
resource "aws_security_group" "alb" {
  name        = "finbank-alb-sg"
  description = "Allow HTTP from the internet to the ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound from ALB to tasks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "finbank-digital" }
}

# ---- Task security group: app port ONLY from the ALB SG ----
resource "aws_security_group" "task" {
  name        = "finbank-task-sg"
  description = "Allow app traffic only from the ALB security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "App port from the ALB SG only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # <-- source is the ALB SG, not a CIDR
  }

  egress {
    description = "Allow all outbound (image pull, logs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "finbank-digital" }
}

# ---- Application Load Balancer ----
resource "aws_lb" "this" {
  name               = "finbank-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  tags = { Project = "finbank-digital" }
}

# ---- Target group (Fargate tasks register here) ----
# target_type = "ip" is REQUIRED for Fargate (awsvpc networking gives each task
# an ENI/IP; you register IPs, not instance IDs).
resource "aws_lb_target_group" "this" {
  name        = "finbank-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Project = "finbank-digital" }
}

# ---- HTTP listener: forward :80 to the target group ----
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

output "alb_dns_name" {
  description = "Public DNS name of the ALB -- this is the URL you hit in a browser."
  value       = aws_lb.this.dns_name
}

output "task_security_group_id" {
  description = "Task SG ID, consumed by the ECS service in 2d."
  value       = aws_security_group.task.id
}

output "target_group_arn" {
  description = "Target group ARN, consumed by the ECS service in 2d."
  value       = aws_lb_target_group.this.arn
}
