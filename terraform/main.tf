# Module instantiations will be added as modules are created.
# See deployment phases in spec Section 11.

# -----------------------------------------------------------------------------
# Availability Zones
# -----------------------------------------------------------------------------

data "aws_availability_zones" "usw2" {
  state = "available"
}

data "aws_availability_zones" "use1" {
  provider = aws.us_east_1
  state    = "available"
}

# -----------------------------------------------------------------------------
# VPCs
# -----------------------------------------------------------------------------

module "onprem_vpc" {
  source             = "./modules/vpc"
  vpc_name           = "Onprem"
  vpc_cidr           = var.onprem_vpc_cidr
  public_subnets     = var.onprem_public_subnets
  private_subnets    = var.onprem_private_subnets
  data_subnets       = var.onprem_data_subnets
  tgw_subnets        = var.onprem_tgw_subnets
  availability_zones = slice(data.aws_availability_zones.usw2.names, 0, 2)
  tags               = { VPC = "onprem", Component = "network" }
}

module "usw_center_vpc" {
  source             = "./modules/vpc"
  vpc_name           = "US-W-CENTER"
  vpc_cidr           = var.usw_center_vpc_cidr
  public_subnets     = var.usw_center_public_subnets
  private_subnets    = var.usw_center_private_subnets
  data_subnets       = var.usw_center_data_subnets
  tgw_subnets        = var.usw_center_tgw_subnets
  availability_zones = slice(data.aws_availability_zones.usw2.names, 0, 2)
  tags               = { VPC = "us-w-center", Component = "network" }
}

module "use_center_vpc" {
  source             = "./modules/vpc"
  vpc_name           = "US-E-CENTER"
  vpc_cidr           = var.use_center_vpc_cidr
  public_subnets     = var.use_center_public_subnets
  private_subnets    = var.use_center_private_subnets
  data_subnets       = var.use_center_data_subnets
  tgw_subnets        = var.use_center_tgw_subnets
  availability_zones = slice(data.aws_availability_zones.use1.names, 0, 2)
  tags               = { VPC = "us-e-center", Component = "network" }
  providers = {
    aws = aws.us_east_1
  }
}

# -----------------------------------------------------------------------------
# VPC Endpoints
# -----------------------------------------------------------------------------

module "onprem_vpc_endpoints" {
  source               = "./modules/vpc-endpoints"
  vpc_id               = module.onprem_vpc.vpc_id
  vpc_name             = "Onprem"
  region               = var.primary_region
  subnet_ids           = module.onprem_vpc.private_subnet_ids
  enable_dsql_endpoint = false
  tags                 = { VPC = "onprem", Component = "network" }
}

module "usw_vpc_endpoints" {
  source               = "./modules/vpc-endpoints"
  vpc_id               = module.usw_center_vpc.vpc_id
  vpc_name             = "US-W-CENTER"
  region               = var.primary_region
  subnet_ids           = module.usw_center_vpc.private_subnet_ids
  enable_dsql_endpoint = true
  tags                 = { VPC = "us-w-center", Component = "network" }
}

module "use_vpc_endpoints" {
  source               = "./modules/vpc-endpoints"
  vpc_id               = module.use_center_vpc.vpc_id
  vpc_name             = "US-E-CENTER"
  region               = var.dr_region
  subnet_ids           = module.use_center_vpc.private_subnet_ids
  enable_dsql_endpoint = true
  tags                 = { VPC = "us-e-center", Component = "network" }
  providers = {
    aws = aws.us_east_1
  }
}

# -----------------------------------------------------------------------------
# Transit Gateways
# -----------------------------------------------------------------------------

module "tgw_west" {
  source          = "./modules/tgw"
  name            = "tgw-us-west-2"
  amazon_side_asn = 65000
  vpc_attachments = {
    onprem = {
      vpc_id     = module.onprem_vpc.vpc_id
      subnet_ids = module.onprem_vpc.tgw_subnet_ids
      vpc_cidr   = var.onprem_vpc_cidr
    }
    usw-center = {
      vpc_id     = module.usw_center_vpc.vpc_id
      subnet_ids = module.usw_center_vpc.tgw_subnet_ids
      vpc_cidr   = var.usw_center_vpc_cidr
    }
  }
  tags = { Component = "network" }
}

module "tgw_east" {
  source          = "./modules/tgw"
  name            = "tgw-us-east-1"
  amazon_side_asn = 65001
  vpc_attachments = {
    use-center = {
      vpc_id     = module.use_center_vpc.vpc_id
      subnet_ids = module.use_center_vpc.tgw_subnet_ids
      vpc_cidr   = var.use_center_vpc_cidr
    }
  }
  tags = { Component = "network" }
  providers = {
    aws = aws.us_east_1
  }
}

# -----------------------------------------------------------------------------
# Cross-VPC Routes (via Transit Gateway)
# -----------------------------------------------------------------------------

# OnPrem private route tables → US-W-CENTER CIDR
resource "aws_route" "onprem_private_to_usw" {
  count = length(module.onprem_vpc.private_route_table_ids)

  route_table_id         = module.onprem_vpc.private_route_table_ids[count.index]
  destination_cidr_block = var.usw_center_vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

# OnPrem private route tables → US-E-CENTER CIDR
resource "aws_route" "onprem_private_to_use" {
  count = length(module.onprem_vpc.private_route_table_ids)

  route_table_id         = module.onprem_vpc.private_route_table_ids[count.index]
  destination_cidr_block = var.use_center_vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

# OnPrem data route tables → US-W-CENTER CIDR
resource "aws_route" "onprem_data_to_usw" {
  count = length(module.onprem_vpc.data_route_table_ids)

  route_table_id         = module.onprem_vpc.data_route_table_ids[count.index]
  destination_cidr_block = var.usw_center_vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

# OnPrem data route tables → US-E-CENTER CIDR
resource "aws_route" "onprem_data_to_use" {
  count = length(module.onprem_vpc.data_route_table_ids)

  route_table_id         = module.onprem_vpc.data_route_table_ids[count.index]
  destination_cidr_block = var.use_center_vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

# US-W-CENTER private route tables → OnPrem CIDR
resource "aws_route" "usw_private_to_onprem" {
  count = length(module.usw_center_vpc.private_route_table_ids)

  route_table_id         = module.usw_center_vpc.private_route_table_ids[count.index]
  destination_cidr_block = var.onprem_vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

# US-W-CENTER private route tables → US-E-CENTER CIDR
resource "aws_route" "usw_private_to_use" {
  count = length(module.usw_center_vpc.private_route_table_ids)

  route_table_id         = module.usw_center_vpc.private_route_table_ids[count.index]
  destination_cidr_block = var.use_center_vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

# US-W-CENTER data route tables → OnPrem CIDR
resource "aws_route" "usw_data_to_onprem" {
  count = length(module.usw_center_vpc.data_route_table_ids)

  route_table_id         = module.usw_center_vpc.data_route_table_ids[count.index]
  destination_cidr_block = var.onprem_vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

# US-W-CENTER data route tables → US-E-CENTER CIDR
resource "aws_route" "usw_data_to_use" {
  count = length(module.usw_center_vpc.data_route_table_ids)

  route_table_id         = module.usw_center_vpc.data_route_table_ids[count.index]
  destination_cidr_block = var.use_center_vpc_cidr
  transit_gateway_id     = module.tgw_west.tgw_id
}

# US-E-CENTER private route tables → OnPrem CIDR
resource "aws_route" "use_private_to_onprem" {
  provider = aws.us_east_1
  count    = length(module.use_center_vpc.private_route_table_ids)

  route_table_id         = module.use_center_vpc.private_route_table_ids[count.index]
  destination_cidr_block = var.onprem_vpc_cidr
  transit_gateway_id     = module.tgw_east.tgw_id
}

# US-E-CENTER private route tables → US-W-CENTER CIDR
resource "aws_route" "use_private_to_usw" {
  provider = aws.us_east_1
  count    = length(module.use_center_vpc.private_route_table_ids)

  route_table_id         = module.use_center_vpc.private_route_table_ids[count.index]
  destination_cidr_block = var.usw_center_vpc_cidr
  transit_gateway_id     = module.tgw_east.tgw_id
}

# US-E-CENTER data route tables → OnPrem CIDR
resource "aws_route" "use_data_to_onprem" {
  provider = aws.us_east_1
  count    = length(module.use_center_vpc.data_route_table_ids)

  route_table_id         = module.use_center_vpc.data_route_table_ids[count.index]
  destination_cidr_block = var.onprem_vpc_cidr
  transit_gateway_id     = module.tgw_east.tgw_id
}

# US-E-CENTER data route tables → US-W-CENTER CIDR
resource "aws_route" "use_data_to_usw" {
  provider = aws.us_east_1
  count    = length(module.use_center_vpc.data_route_table_ids)

  route_table_id         = module.use_center_vpc.data_route_table_ids[count.index]
  destination_cidr_block = var.usw_center_vpc_cidr
  transit_gateway_id     = module.tgw_east.tgw_id
}

# -----------------------------------------------------------------------------
# TGW Inter-Region Peering
# -----------------------------------------------------------------------------

module "tgw_peering" {
  source                       = "./modules/tgw-peering"
  requester_tgw_id             = module.tgw_west.tgw_id
  requester_tgw_route_table_id = module.tgw_west.tgw_route_table_id
  accepter_tgw_id              = module.tgw_east.tgw_id
  accepter_tgw_route_table_id  = module.tgw_east.tgw_route_table_id
  accepter_region              = var.dr_region
  requester_cidrs_to_route     = [var.use_center_vpc_cidr]
  accepter_cidrs_to_route      = [var.onprem_vpc_cidr, var.usw_center_vpc_cidr]
  tags                         = { Component = "network" }
  providers = {
    aws          = aws
    aws.accepter = aws.us_east_1
  }
}

# -----------------------------------------------------------------------------
# Caller Identity (for secret header values)
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# CloudFront + ALB Ingress
# -----------------------------------------------------------------------------

module "onprem_ingress" {
  source              = "./modules/cloudfront-alb"
  vpc_id              = module.onprem_vpc.vpc_id
  vpc_name            = "Onprem"
  public_subnet_ids   = module.onprem_vpc.public_subnet_ids
  custom_header_value = "onprem-secret-${data.aws_caller_identity.current.account_id}"
  tags                = { VPC = "onprem", Component = "ingress" }
}

module "usw_ingress" {
  source              = "./modules/cloudfront-alb"
  vpc_id              = module.usw_center_vpc.vpc_id
  vpc_name            = "US-W-CENTER"
  public_subnet_ids   = module.usw_center_vpc.public_subnet_ids
  custom_header_value = "usw-secret-${data.aws_caller_identity.current.account_id}"
  tags                = { VPC = "us-w-center", Component = "ingress" }
}

module "use_ingress" {
  source              = "./modules/cloudfront-alb"
  vpc_id              = module.use_center_vpc.vpc_id
  vpc_name            = "US-E-CENTER"
  public_subnet_ids   = module.use_center_vpc.public_subnet_ids
  custom_header_value = "use-secret-${data.aws_caller_identity.current.account_id}"
  tags                = { VPC = "us-e-center", Component = "ingress" }
  providers = {
    aws = aws.us_east_1
  }
}

# -----------------------------------------------------------------------------
# Route 53 Failover (conditional on domain_name)
# -----------------------------------------------------------------------------

module "route53_failover" {
  count                       = var.domain_name != "" ? 1 : 0
  source                      = "./modules/route53-failover"
  domain_name                 = var.domain_name
  primary_cloudfront_domain   = module.usw_ingress.cloudfront_domain_name
  secondary_cloudfront_domain = module.use_ingress.cloudfront_domain_name
  primary_alb_dns             = module.usw_ingress.alb_dns_name
  secondary_alb_dns           = module.use_ingress.alb_dns_name
  tags                        = { Component = "network" }
}
