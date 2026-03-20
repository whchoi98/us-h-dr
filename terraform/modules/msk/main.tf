terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "msk" {
  name_prefix = "${var.cluster_name}-msk-"
  vpc_id      = var.vpc_id

  # TLS port
  ingress {
    description     = "Kafka TLS"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  # IAM auth port
  ingress {
    description     = "Kafka IAM auth"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  # Self-referencing for inter-broker communication
  ingress {
    description = "Inter-broker"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-msk-sg"
  })
}

# -----------------------------------------------------------------------------
# MSK Configuration
# -----------------------------------------------------------------------------

resource "aws_msk_configuration" "this" {
  name           = "${var.cluster_name}-config"
  kafka_versions = [var.kafka_version]

  server_properties = <<PROPS
auto.create.topics.enable=true
default.replication.factor=3
min.insync.replicas=2
num.partitions=6
PROPS
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.cluster_name}"
  retention_in_days = 14

  tags = var.tags
}

# -----------------------------------------------------------------------------
# MSK Cluster
# -----------------------------------------------------------------------------

resource "aws_msk_cluster" "this" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  client_authentication {
    sasl {
      iam = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = merge(var.tags, { Name = var.cluster_name })
}
