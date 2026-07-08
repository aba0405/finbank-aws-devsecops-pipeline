########################################
# Phase 2b: IAM roles for ECS Fargate
#
# Two DISTINCT roles, a point worth understanding:
#
#  1. TASK EXECUTION ROLE - assumed by the Fargate infrastructure/ECS agent
#     (not your code). It pulls the image from ECR and ships container logs to
#     CloudWatch. Always needs permissions. We attach the AWS-managed
#     AmazonECSTaskExecutionRolePolicy, which grants exactly ECR-pull +
#     CloudWatch-logs and nothing else.
#
#  2. TASK ROLE - assumed by YOUR APPLICATION code inside the container, for
#     any AWS API calls it makes. Our app makes NONE (it just serves HTTP), so
#     this role is intentionally EMPTY. That is the secure, correct answer:
#     the workload gets zero AWS permissions it doesn't need. If the app later
#     needed to read a Secret or hit S3, we'd attach a scoped policy here.
#
# Both roles trust ecs-tasks.amazonaws.com to assume them.
########################################

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ---- Task execution role (platform pulls image, writes logs) ----
resource "aws_iam_role" "task_execution" {
  name               = "finbank-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = {
    Project = "finbank-digital"
  }
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---- Task role (the app's own identity) -- intentionally empty ----
resource "aws_iam_role" "task" {
  name               = "finbank-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  # No policy attachments. The application makes no AWS API calls, so it needs
  # no permissions. Least privilege = grant nothing when nothing is required.

  tags = {
    Project = "finbank-digital"
  }
}

output "task_execution_role_arn" {
  description = "Execution role ARN for the ECS task definition."
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "Task (app) role ARN for the ECS task definition."
  value       = aws_iam_role.task.arn
}
