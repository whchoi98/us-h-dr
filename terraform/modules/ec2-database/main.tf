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

resource "aws_iam_role" "db" {
  name = "ec2-database-${var.vpc_name}-role"
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

resource "aws_iam_role_policy_attachment" "db" {
  count      = length(var.iam_policies)
  policy_arn = var.iam_policies[count.index]
  role       = aws_iam_role.db.name
}

resource "aws_iam_instance_profile" "db" {
  name = "ec2-database-${var.vpc_name}-profile"
  role = aws_iam_role.db.name

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EC2 Instances
# -----------------------------------------------------------------------------

resource "aws_instance" "db" {
  for_each = var.instances

  ami                    = data.aws_ami.al2023_arm64.id
  instance_type          = each.value.instance_type
  subnet_id              = each.value.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.db.name
  vpc_security_group_ids = each.value.sg_ids

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/${each.value.user_data_file}", {
    broker_id         = try(each.value.name, "")
    private_ip        = ""
    zookeeper_connect = ""
  })

  tags = merge(var.tags, {
    Name = each.value.name
  })
}
