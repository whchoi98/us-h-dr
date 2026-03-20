terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# -----------------------------------------------------------------------------
# SNS Topic for Alerts
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "dr-lab-alerts-${replace(var.region, "-", "")}"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.sns_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# -----------------------------------------------------------------------------
# MSK CloudWatch Alarms
# -----------------------------------------------------------------------------

# UnderReplicatedPartitions - triggers when any partition is under-replicated
resource "aws_cloudwatch_metric_alarm" "msk_under_replicated" {
  alarm_name          = "${var.msk_cluster_name}-under-replicated"
  alarm_description   = "MSK cluster has under-replicated partitions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnderReplicatedPartitions"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    "Cluster Name" = var.msk_cluster_name
  }

  tags = var.tags
}

# OfflinePartitionsCount - critical: partition has no leader
resource "aws_cloudwatch_metric_alarm" "msk_offline_partitions" {
  alarm_name          = "${var.msk_cluster_name}-offline-partitions"
  alarm_description   = "MSK cluster has offline partitions (no leader)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "OfflinePartitionsCount"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    "Cluster Name" = var.msk_cluster_name
  }

  tags = var.tags
}

# ActiveControllerCount - should always be exactly 1
resource "aws_cloudwatch_metric_alarm" "msk_active_controller" {
  alarm_name          = "${var.msk_cluster_name}-no-active-controller"
  alarm_description   = "MSK cluster has no active controller"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ActiveControllerCount"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    "Cluster Name" = var.msk_cluster_name
  }

  tags = var.tags
}

# KafkaDataLogsDiskUsed - disk usage above 85%
resource "aws_cloudwatch_metric_alarm" "msk_disk_usage" {
  alarm_name          = "${var.msk_cluster_name}-disk-usage-high"
  alarm_description   = "MSK broker disk usage exceeds 85%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "KafkaDataLogsDiskUsed"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    "Cluster Name" = var.msk_cluster_name
  }

  tags = var.tags
}

# CpuUser - CPU usage above 80%
resource "aws_cloudwatch_metric_alarm" "msk_cpu_usage" {
  alarm_name          = "${var.msk_cluster_name}-cpu-usage-high"
  alarm_description   = "MSK broker CPU usage exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CpuUser"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    "Cluster Name" = var.msk_cluster_name
  }

  tags = var.tags
}

# MemoryUsed - memory usage above 85%
resource "aws_cloudwatch_metric_alarm" "msk_memory_usage" {
  alarm_name          = "${var.msk_cluster_name}-memory-usage-high"
  alarm_description   = "MSK broker memory usage exceeds 85%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HeapMemoryAfterGC"
  namespace           = "AWS/Kafka"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    "Cluster Name" = var.msk_cluster_name
  }

  tags = var.tags
}
