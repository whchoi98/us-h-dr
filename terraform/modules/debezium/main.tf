terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# -----------------------------------------------------------------------------
# IAM Role and Instance Profile
# -----------------------------------------------------------------------------

resource "aws_iam_role" "debezium" {
  name = "debezium-${var.vpc_name}-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "debezium_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.debezium.name
}

resource "aws_iam_instance_profile" "debezium" {
  name = "debezium-${var.vpc_name}-profile"
  role = aws_iam_role.debezium.name

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "debezium" {
  name        = "debezium-${var.vpc_name}-sg"
  description = "Security group for Debezium Kafka Connect in ${var.vpc_name}"
  vpc_id      = var.vpc_id

  # Allow Kafka Connect REST API from VSCode
  ingress {
    description     = "Kafka Connect REST API from VSCode"
    from_port       = 8083
    to_port         = 8083
    protocol        = "tcp"
    security_groups = [var.vscode_sg_id]
  }

  # Allow all outbound
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "debezium-${var.vpc_name}-sg"
  })
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "debezium" {
  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.debezium.name
  vpc_security_group_ids = [aws_security_group.debezium.id, var.kafka_sg_id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    kafka_brokers = var.kafka_brokers
  })

  tags = merge(var.tags, {
    Name = "debezium-${var.vpc_name}"
  })
}
