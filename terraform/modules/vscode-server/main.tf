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

resource "aws_iam_role" "vscode" {
  name = "vscode-server-${var.vpc_name}-role"
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

resource "aws_iam_role_policy_attachment" "vscode_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.vscode.name
}

resource "aws_iam_role_policy_attachment" "vscode_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.vscode.name
}

resource "aws_iam_instance_profile" "vscode" {
  name = "vscode-server-${var.vpc_name}-profile"
  role = aws_iam_role.vscode.name

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------

resource "aws_security_group" "vscode" {
  name        = "vscode-server-${var.vpc_name}-sg"
  description = "Security group for VSCode server in ${var.vpc_name}"
  vpc_id      = var.vpc_id

  # Allow TCP 8888 from ALB security group
  ingress {
    description     = "code-server from ALB"
    from_port       = 8888
    to_port         = 8888
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
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
    Name = "vscode-server-${var.vpc_name}-sg"
  })
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "vscode" {
  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.vscode.name
  vpc_security_group_ids = [aws_security_group.vscode.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    vscode_password = var.password
  })

  tags = merge(var.tags, {
    Name = "vscode-server-${var.vpc_name}"
  })
}
