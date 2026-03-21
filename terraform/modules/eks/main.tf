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

data "aws_vpc" "this" {
  id = var.vpc_id
}

# -----------------------------------------------------------------------------
# IAM Role for EKS Cluster
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eks_cluster" {
  name = "${var.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# -----------------------------------------------------------------------------
# IAM Role for EKS Nodes
# -----------------------------------------------------------------------------

resource "aws_iam_role" "eks_node" {
  name = "${var.cluster_name}-node-role"
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

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_ssm_managed" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_node.name
}

# -----------------------------------------------------------------------------
# Security Group for EKS Nodes
# -----------------------------------------------------------------------------

resource "aws_security_group" "eks_node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for EKS nodes in ${var.cluster_name}"
  vpc_id      = var.vpc_id

  # Allow all traffic from self (node-to-node communication)
  ingress {
    description = "Allow all from self"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow HTTPS from VPC CIDR
  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
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
    Name = "${var.cluster_name}-node-sg"
  })
}

# -----------------------------------------------------------------------------
# KMS Key for EKS Secrets Encryption
# -----------------------------------------------------------------------------

resource "aws_kms_key" "eks_secrets" {
  description             = "KMS key for EKS secrets encryption - ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-eks-secrets-key"
  })
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# -----------------------------------------------------------------------------
# eksctl Configuration Template
# -----------------------------------------------------------------------------

resource "local_file" "eksctl_config" {
  content = templatefile("${path.module}/eksctl-config.yaml.tpl", {
    cluster_name               = var.cluster_name
    region                     = var.region
    eks_version                = var.eks_version
    vpc_id                     = var.vpc_id
    private_subnet_a           = var.private_subnet_ids[0]
    private_subnet_b           = var.private_subnet_ids[1]
    az_a                       = var.availability_zones[0]
    az_b                       = var.availability_zones[1]
    node_type                  = var.node_type
    node_count                 = var.node_count
    node_role_arn              = aws_iam_role.eks_node.arn
    secrets_encryption_key_arn = aws_kms_key.eks_secrets.arn
  })
  filename = "${path.root}/../shared/configs/eksctl-${var.cluster_name}.yaml"
}
