terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.accepter]
    }
  }
}

################################################################################
# Data: Current Account
################################################################################

data "aws_caller_identity" "this" {}

################################################################################
# Peering Attachment (requester side)
################################################################################

resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  transit_gateway_id      = var.requester_tgw_id
  peer_transit_gateway_id = var.accepter_tgw_id
  peer_region             = var.accepter_region
  peer_account_id         = data.aws_caller_identity.this.account_id

  tags = merge(var.tags, {
    Name = "tgw-peering-requester"
  })
}

################################################################################
# Peering Attachment Accepter
################################################################################

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  provider = aws.accepter

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.this.id

  tags = merge(var.tags, {
    Name = "tgw-peering-accepter"
  })
}

################################################################################
# Requester Routes (route accepter CIDRs via peering)
################################################################################

resource "aws_ec2_transit_gateway_route" "requester" {
  count = length(var.requester_cidrs_to_route)

  destination_cidr_block         = var.requester_cidrs_to_route[count.index]
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this.id
  transit_gateway_route_table_id = var.requester_tgw_route_table_id
}

################################################################################
# Accepter Routes (route requester CIDRs via peering)
################################################################################

resource "aws_ec2_transit_gateway_route" "accepter" {
  provider = aws.accepter
  count    = length(var.accepter_cidrs_to_route)

  destination_cidr_block         = var.accepter_cidrs_to_route[count.index]
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this.id
  transit_gateway_route_table_id = var.accepter_tgw_route_table_id
}
