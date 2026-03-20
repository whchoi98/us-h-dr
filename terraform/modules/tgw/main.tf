terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

################################################################################
# Transit Gateway
################################################################################

resource "aws_ec2_transit_gateway" "this" {
  amazon_side_asn                 = var.amazon_side_asn
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, {
    Name = var.name
  })
}

################################################################################
# Route Table
################################################################################

resource "aws_ec2_transit_gateway_route_table" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-rt"
  })
}

################################################################################
# VPC Attachments
################################################################################

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each = var.vpc_attachments

  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })
}

################################################################################
# Route Table Associations
################################################################################

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each = var.vpc_attachments

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

################################################################################
# Routes (one per VPC CIDR)
################################################################################

resource "aws_ec2_transit_gateway_route" "this" {
  for_each = var.vpc_attachments

  destination_cidr_block         = each.value.vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}
