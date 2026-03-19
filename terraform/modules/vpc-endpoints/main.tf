################################################################################
# VPC Endpoint Security Group
################################################################################

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "vpce" {
  name_prefix = "${var.vpc_name}-vpce-"
  description = "Security group for VPC endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.this.cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-vpce-sg"
  })
}

################################################################################
# Interface VPC Endpoints
################################################################################

locals {
  ssm_services = [
    "ssm",
    "ssmmessages",
    "ec2messages",
  ]

  dsql_services = var.enable_dsql_endpoint ? ["dsql"] : []

  all_services = concat(local.ssm_services, local.dsql_services)
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.all_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-${each.key}-vpce"
  })
}
