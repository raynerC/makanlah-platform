data "aws_region" "current" {}

locals {
  region = data.aws_region.current.region
}

# ---- alerting channel ----

resource "aws_sns_topic" "alerts" {
  name              = "${var.name}-alerts"
  kms_master_key_id = "alias/aws/sns" # AWS-managed key: encryption at rest, no CMK cost
}

# the subscription stays 'pending confirmation' until the email owner clicks
# the link AWS sends — alarms fire regardless, delivery starts after confirm
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---- alarms: page on symptoms, not causes ----

# name is load-bearing: deploy.yml watches this exact alarm as its rollout gate
resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "${var.name}-alb-target-5xx"
  alarm_description   = "Backend 5xx burst — deploy gate + paging signal"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "p95_latency" {
  alarm_name          = "${var.name}-p95-latency"
  alarm_description   = "p95 response time above SLO (${var.p95_threshold_seconds}s)"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.p95_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name}-dlq-not-empty"
  alarm_description   = "Poison messages in the DLQ — something cannot be processed"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = var.dlq_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# RunningTaskCount comes from Container Insights (enabled on the cluster)
resource "aws_cloudwatch_metric_alarm" "service_down" {
  for_each = toset(var.service_names)

  alarm_name          = "${var.name}-${each.value}-no-running-tasks"
  alarm_description   = "Service has zero running tasks (crash loop or failed deploy)"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching" # no metric = nothing running

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ---- dashboard ----

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "ALB latency (p50 / p95 / p99)"
          region = local.region
          stat   = "p95"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
          annotations = { horizontal = [{ label = "p95 SLO", value = var.p95_threshold_seconds }] }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Requests & errors"
          region = local.region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "requests" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { stat = "Sum", label = "5xx (target)" }],
            [".", "HTTPCode_ELB_5XX_Count", ".", ".", { stat = "Sum", label = "5xx (elb)" }],
            [".", "HTTPCode_Target_4XX_Count", ".", ".", { stat = "Sum", label = "4xx" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Order events queue"
          region = local.region
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.queue_name, { stat = "Maximum", label = "queue depth" }],
            [".", "ApproximateAgeOfOldestMessage", ".", ".", { stat = "Maximum", label = "oldest message (s)" }],
            [".", "ApproximateNumberOfMessagesVisible", ".", var.dlq_name, { stat = "Maximum", label = "DLQ depth" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "ECS running tasks (autoscaling)"
          region = local.region
          period = 60
          metrics = [
            for s in var.service_names :
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.cluster_name, "ServiceName", s, { stat = "Maximum", label = s }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 24, height = 6
        properties = {
          title  = "ECS CPU utilization %"
          region = local.region
          period = 60
          metrics = [
            for s in var.service_names :
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", s, { stat = "Average", label = s }]
          ]
          annotations = { horizontal = [{ label = "scale-out target", value = 60 }] }
        }
      },
    ]
  })
}
