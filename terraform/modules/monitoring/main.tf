resource "aws_cloudwatch_log_group" "processing" {
  name              = var.log_group_name
  retention_in_days = 30

  tags = {
    Project = var.project_name
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Project = var.project_name
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarm: SQS queue depth - worker may be stuck or underpowered
resource "aws_cloudwatch_metric_alarm" "sqs_depth" {
  alarm_name          = "${var.project_name}-sqs-depth-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "SQS queue depth > 10 - worker may be stuck or need scaling"

  dimensions = {
    QueueName = var.sqs_queue_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# Alarm: EC2 CPU - may indicate processing bottleneck
resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "${var.project_name}-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EC2 CPU > 80% - consider upgrading instance or adding workers"

  dimensions = {
    InstanceId = var.ec2_instance_id
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "SQS Queue Depth"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.sqs_queue_name]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", var.ec2_instance_id]
          ]
          period = 60
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 6
        width  = 24
        height = 8
        properties = {
          title  = "Processing Logs (live)"
          query  = "SOURCE '${var.log_group_name}' | fields @timestamp, level, message, job_id, input_key, ndvi_mean | sort @timestamp desc | limit 50"
          region = var.aws_region
          view   = "table"
        }
      }
    ]
  })
}
