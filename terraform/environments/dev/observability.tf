########################################
# Phase 4: Observability
#
#  - SNS topic + email subscription: the alert channel. Email subscription
#    comes up PENDING -- you must click the confirmation link AWS emails you.
#  - EventBridge rule: fires on CodePipeline execution FAILED -> SNS. This is
#    the "a gate blocked a deploy -> team gets emailed" link. Directly answers
#    FinBank's "no deployment visibility" problem.
#  - CloudWatch alarms: ECS running task count, ALB 5xx, ALB unhealthy hosts.
#  - Dashboard: single-pane view of pipeline + app health.
########################################

variable "alert_email" {
  description = "Email address to receive alerts. You must confirm the SNS subscription via the link AWS emails you."
  type        = string
}

# ---- SNS topic + email subscription ----
resource "aws_sns_topic" "alerts" {
  name = "finbank-alerts"
  tags = { Project = "finbank-digital" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
  # Subscription is PENDING until you click the confirmation link in your inbox.
}

# Allow EventBridge + CloudWatch to publish to the topic.
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeAndCloudWatch"
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com", "cloudwatch.amazonaws.com"] }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# ---- EventBridge: pipeline failure -> SNS ----
resource "aws_cloudwatch_event_rule" "pipeline_failed" {
  name        = "finbank-pipeline-failed"
  description = "Fires when the FinBank pipeline execution fails (e.g. a security gate blocks a deploy)."

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      state    = ["FAILED"]
      pipeline = ["finbank-pipeline"]
    }
  })

  tags = { Project = "finbank-digital" }
}

resource "aws_cloudwatch_event_target" "pipeline_failed_sns" {
  rule      = aws_cloudwatch_event_rule.pipeline_failed.name
  target_id = "finbank-pipeline-failed-sns"
  arn       = aws_sns_topic.alerts.arn

  # Turn the raw event into a readable email message.
  input_transformer {
    input_paths = {
      pipeline = "$.detail.pipeline"
      state    = "$.detail.state"
      time     = "$.time"
    }
    input_template = "\"FinBank ALERT: pipeline <pipeline> execution <state> at <time>. A stage failed -- likely a security gate blocked a non-compliant build. Check CodePipeline.\""
  }
}

# ---- CloudWatch alarm: ECS running task count too low ----
resource "aws_cloudwatch_metric_alarm" "ecs_task_count" {
  alarm_name          = "finbank-ecs-running-tasks-low"
  alarm_description   = "Fires if the ECS service has fewer than 1 running task."
  namespace           = "AWS/ECS"
  metric_name         = "RunningTaskCount"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 2
  period              = 60
  statistic           = "Average"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = { Project = "finbank-digital" }
}

# ---- CloudWatch alarm: ALB 5xx errors ----
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "finbank-alb-5xx-errors"
  alarm_description   = "Fires if the ALB returns 5xx errors (app or backend failing)."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  evaluation_periods  = 1
  period              = 60
  statistic           = "Sum"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = { Project = "finbank-digital" }
}

# ---- CloudWatch alarm: ALB unhealthy hosts ----
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "finbank-alb-unhealthy-hosts"
  alarm_description   = "Fires if the target group has any unhealthy hosts."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 2
  period              = 60
  statistic           = "Average"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
    TargetGroup  = aws_lb_target_group.this.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = { Project = "finbank-digital" }
}

# ---- CloudWatch dashboard ----
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "finbank-observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "ECS Running Tasks"
          region = var.region
          metrics = [
            ["AWS/ECS", "RunningTaskCount", "ClusterName", aws_ecs_cluster.this.name, "ServiceName", aws_ecs_service.app.name]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "ALB Request Count & 5xx"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.this.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.this.arn_suffix]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Target Health (healthy vs unhealthy)"
          region = var.region
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", aws_lb.this.arn_suffix, "TargetGroup", aws_lb_target_group.this.arn_suffix]
          ]
          period = 60
          stat   = "Average"
        }
      }
    ]
  })
}

output "sns_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "SNS topic for FinBank alerts."
}

output "dashboard_url" {
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=finbank-observability"
  description = "Direct link to the CloudWatch dashboard."
}
