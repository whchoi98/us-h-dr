# -----------------------------------------------------------------------------
# IAM Role for MSK Replicator
# -----------------------------------------------------------------------------

resource "aws_iam_role" "replicator" {
  name = "${var.replicator_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "kafka.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "replicator" {
  name = "${var.replicator_name}-policy"
  role = aws_iam_role.replicator.id
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
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# MSK Replicator (Source -> Target)
# -----------------------------------------------------------------------------

resource "aws_msk_replicator" "this" {
  replicator_name            = var.replicator_name
  description                = "Replication from source to target MSK cluster"
  service_execution_role_arn = aws_iam_role.replicator.arn

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = var.source_msk_arn
    }
    vpc_config {
      subnet_ids          = var.source_subnet_ids
      security_groups_ids = var.source_security_group_ids
    }
  }

  kafka_cluster {
    amazon_msk_cluster {
      msk_cluster_arn = var.target_msk_arn
    }
    vpc_config {
      subnet_ids          = var.target_subnet_ids
      security_groups_ids = var.target_security_group_ids
    }
  }

  replication_info_list {
    source_kafka_cluster_arn = var.source_msk_arn
    target_kafka_cluster_arn = var.target_msk_arn
    target_compression_type  = "GZIP"

    topic_replication {
      topics_to_replicate                  = [".*"]
      copy_topic_configurations            = true
      copy_access_control_lists_for_topics = false
      detect_and_copy_new_topics           = true

      topic_name_configuration {
        type = "PREFIXED_WITH_SOURCE_CLUSTER_ALIAS"
      }

      starting_position {
        type = "LATEST"
      }
    }

    consumer_group_replication {
      consumer_groups_to_replicate        = [".*"]
      detect_and_copy_new_consumer_groups = true
      synchronise_consumer_group_offsets  = true
    }
  }

  tags = var.tags
}
