########################################
# Phase 2d: ECS cluster + task definition + service
#
# Key details worth understanding:
#  - LOG GROUP is created here, not in Phase 4. Without it, a crashing container
#    produces no diagnostics and the task dies silently. Logs are how we debug.
#  - assign_public_ip = true is REQUIRED given our public-subnet/no-NAT design.
#    The task needs a public IP to reach ECR and pull the image. Set it false
#    and you get an image-pull timeout -- the classic Fargate failure caused by
#    exactly this cost tradeoff.
#  - network_mode "awsvpc" is the only option for Fargate; each task gets its
#    own ENI, which is why the target group uses target_type = "ip".
#  - 1 task, 0.25 vCPU / 512MB: cheapest viable. Production would run >=2 tasks
#    across AZs for availability. Noted as a known limitation.
########################################

variable "image_tag" {
  description = "Image tag to deploy. Matches what you pushed to ECR."
  type        = string
  default     = "v1"
}

# ---- CloudWatch log group for container output ----
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/finbank-digital"
  retention_in_days = 7 # short retention keeps cost near zero

  tags = { Project = "finbank-digital" }
}

# ---- ECS cluster (free; just a logical grouping) ----
resource "aws_ecs_cluster" "this" {
  name = "finbank-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # Container Insights costs money; off for this demo
  }

  tags = { Project = "finbank-digital" }
}

# ---- Task definition: the blueprint ----
resource "aws_ecs_task_definition" "app" {
  family                   = "finbank-digital"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256" # 0.25 vCPU
  memory                   = "512" # 512 MB

  # Two DIFFERENT roles -- see iam-roles.tf for why.
  execution_role_arn = aws_iam_role.task_execution.arn # platform: pull image, write logs
  task_role_arn      = aws_iam_role.task.arn           # app identity: intentionally empty

  container_definitions = jsonencode([
    {
      name      = "finbank-app"
      image     = "${module.ecr.repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]

      # Stamp the running container with build metadata (see app.py).
      environment = [
        { name = "APP_VERSION", value = var.image_tag },
        { name = "GIT_SHA", value = "phase2" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = { Project = "finbank-digital" }
}

# ---- Service: keeps the task running and registers it with the ALB ----
resource "aws_ecs_service" "app" {
  name            = "finbank-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true # REQUIRED: no NAT, so the task needs a public IP to pull from ECR
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "finbank-app"
    container_port   = 8080
  }

  # Don't try to register targets before the listener exists.
  depends_on = [aws_lb_listener.http]

  tags = { Project = "finbank-digital" }
}

output "app_url" {
  description = "Hit this in a browser once the task is healthy."
  value       = "http://${aws_lb.this.dns_name}"
}
