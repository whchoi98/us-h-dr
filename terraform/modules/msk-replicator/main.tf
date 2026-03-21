terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# -----------------------------------------------------------------------------
# MSK Replicator (Source -> Target)
# NOTE: IAM role and cluster policies are created in main.tf (cross-region)
# -----------------------------------------------------------------------------

resource "aws_msk_replicator" "this" {
  replicator_name            = var.replicator_name
  description                = "Replication from source to target MSK cluster"
  service_execution_role_arn = var.service_execution_role_arn

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
