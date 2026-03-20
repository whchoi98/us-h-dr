terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# -----------------------------------------------------------------------------
# Custom Plugin (from S3)
# -----------------------------------------------------------------------------

resource "aws_mskconnect_custom_plugin" "this" {
  name         = "${var.connector_name}-plugin"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = "arn:aws:s3:::${var.plugin_s3_bucket}"
      file_key   = var.plugin_s3_key
    }
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# IAM Role for MSK Connect
# -----------------------------------------------------------------------------

resource "aws_iam_role" "msk_connect" {
  name = "${var.connector_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "kafkaconnect.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "msk_connect" {
  name = "${var.connector_name}-policy"
  role = aws_iam_role.msk_connect.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["dsql:*"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Connector Logs
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "connector" {
  name              = "/aws/msk-connect/${var.connector_name}"
  retention_in_days = 14

  tags = var.tags
}

# -----------------------------------------------------------------------------
# MSK Connect Connector
# -----------------------------------------------------------------------------

resource "aws_mskconnect_connector" "this" {
  name = var.connector_name

  kafkaconnect_version = "2.7.1"

  capacity {
    provisioned_capacity {
      mcu_count    = 1
      worker_count = var.worker_count
    }
  }

  connector_configuration = merge(
    {
      "connector.class" = var.connector_class
    },
    var.connector_configuration
  )

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = var.msk_bootstrap_servers
      vpc {
        subnets         = var.subnet_ids
        security_groups = var.security_group_ids
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "IAM"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.this.arn
      revision = aws_mskconnect_custom_plugin.this.latest_revision
    }
  }

  service_execution_role_arn = aws_iam_role.msk_connect.arn

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.connector.name
      }
    }
  }

  tags = var.tags
}
