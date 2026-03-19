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

# -----------------------------------------------------------------------------
# EKS Clusters
# -----------------------------------------------------------------------------

module "onprem_eks" {
  source             = "./modules/eks"
  cluster_name       = "onprem-eks"
  vpc_id             = module.onprem_vpc.vpc_id
  private_subnet_ids = module.onprem_vpc.private_subnet_ids
  eks_version        = var.eks_version
  node_type          = var.eks_node_type
  node_count         = var.eks_node_count
  region             = var.primary_region
  availability_zones = slice(data.aws_availability_zones.usw2.names, 0, 2)
  tags               = { VPC = "onprem", Component = "eks" }
}

module "usw_eks" {
  source             = "./modules/eks"
  cluster_name       = "usw-eks"
  vpc_id             = module.usw_center_vpc.vpc_id
  private_subnet_ids = module.usw_center_vpc.private_subnet_ids
  eks_version        = var.eks_version
  node_type          = var.eks_node_type
  node_count         = var.eks_node_count
  region             = var.primary_region
  availability_zones = slice(data.aws_availability_zones.usw2.names, 0, 2)
  tags               = { VPC = "us-w-center", Component = "eks" }
}

module "use_eks" {
  source             = "./modules/eks"
  cluster_name       = "use-eks"
  vpc_id             = module.use_center_vpc.vpc_id
  private_subnet_ids = module.use_center_vpc.private_subnet_ids
  eks_version        = var.eks_version
  node_type          = var.eks_node_type
  node_count         = var.eks_node_count
  region             = var.dr_region
  availability_zones = slice(data.aws_availability_zones.use1.names, 0, 2)
  tags               = { VPC = "us-e-center", Component = "eks" }
  providers = {
    aws = aws.us_east_1
  }
}

# -----------------------------------------------------------------------------
# VSCode Server (OnPrem VPC only)
# -----------------------------------------------------------------------------

module "onprem_vscode" {
  source                = "./modules/vscode-server"
  instance_type         = var.vscode_instance_type
  vpc_id                = module.onprem_vpc.vpc_id
  subnet_id             = module.onprem_vpc.private_subnet_ids[0]
  alb_security_group_id = module.onprem_ingress.alb_security_group_id
  password              = var.vscode_password
  vpc_name              = "Onprem"
  tags                  = { VPC = "onprem", Component = "vscode" }
}

# =============================================================================
# TASK 12: OnPrem Data Layer - Security Groups
# =============================================================================

# -----------------------------------------------------------------------------
# OnPrem Security Groups
# -----------------------------------------------------------------------------

# Debezium SG (created early because other SGs reference it)
resource "aws_security_group" "sg_debezium" {
  name        = "onprem-debezium-sg"
  description = "Security group for Debezium Kafka Connect"
  vpc_id      = module.onprem_vpc.vpc_id

  ingress {
    description     = "Kafka Connect REST API from VSCode"
    from_port       = 8083
    to_port         = 8083
    protocol        = "tcp"
    security_groups = [module.onprem_vscode.security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "onprem", Component = "data", Name = "onprem-debezium-sg" }
}

# MirrorMaker 2 SG (outbound only)
resource "aws_security_group" "sg_mm2" {
  name        = "onprem-mm2-sg"
  description = "Security group for MirrorMaker 2"
  vpc_id      = module.onprem_vpc.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "onprem", Component = "data", Name = "onprem-mm2-sg" }
}

# PostgreSQL SG
resource "aws_security_group" "sg_postgresql" {
  name        = "onprem-postgresql-sg"
  description = "Security group for PostgreSQL"
  vpc_id      = module.onprem_vpc.vpc_id

  ingress {
    description     = "PostgreSQL from Debezium"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_debezium.id]
  }

  ingress {
    description     = "PostgreSQL from VSCode"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.onprem_vscode.security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "onprem", Component = "data", Name = "onprem-postgresql-sg" }
}

# MongoDB SG (OnPrem)
resource "aws_security_group" "sg_mongodb" {
  name        = "onprem-mongodb-sg"
  description = "Security group for MongoDB"
  vpc_id      = module.onprem_vpc.vpc_id

  ingress {
    description     = "MongoDB from Debezium"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_debezium.id]
  }

  ingress {
    description     = "MongoDB from VSCode"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [module.onprem_vscode.security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "onprem", Component = "data", Name = "onprem-mongodb-sg" }
}

# Kafka SG (OnPrem)
resource "aws_security_group" "sg_kafka" {
  name        = "onprem-kafka-sg"
  description = "Security group for Apache Kafka brokers"
  vpc_id      = module.onprem_vpc.vpc_id

  ingress {
    description     = "Kafka from Debezium"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_debezium.id]
  }

  ingress {
    description = "Kafka from self (inter-broker)"
    from_port   = 9092
    to_port     = 9093
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description     = "Kafka from MM2"
    from_port       = 9092
    to_port         = 9093
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_mm2.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "onprem", Component = "data", Name = "onprem-kafka-sg" }
}

# -----------------------------------------------------------------------------
# US-W Security Groups
# -----------------------------------------------------------------------------

# MSK Connect SG (US-W) - outbound only
resource "aws_security_group" "sg_msk_connect_usw" {
  name        = "usw-msk-connect-sg"
  description = "Security group for MSK Connect in US-W"
  vpc_id      = module.usw_center_vpc.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "us-w-center", Component = "data", Name = "usw-msk-connect-sg" }
}

# MSK SG (US-W)
resource "aws_security_group" "sg_msk_usw" {
  name        = "usw-msk-sg"
  description = "Security group for MSK in US-W"
  vpc_id      = module.usw_center_vpc.vpc_id

  ingress {
    description     = "Kafka TLS from MM2 via TGW"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_msk_connect_usw.id]
  }

  ingress {
    description = "Kafka TLS from OnPrem MM2 via TGW"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.onprem_vpc_cidr]
  }

  ingress {
    description     = "Kafka IAM auth from MSK Connect"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_msk_connect_usw.id]
  }

  ingress {
    description = "Kafka IAM auth from OnPrem MM2 via TGW"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.onprem_vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "us-w-center", Component = "data", Name = "usw-msk-sg" }
}

# DSQL Endpoint SG (US-W)
resource "aws_security_group" "sg_dsql_endpoint_usw" {
  name        = "usw-dsql-endpoint-sg"
  description = "Security group for DSQL VPC endpoint in US-W"
  vpc_id      = module.usw_center_vpc.vpc_id

  ingress {
    description     = "HTTPS from MSK Connect"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_msk_connect_usw.id]
  }

  ingress {
    description     = "HTTPS from EKS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.usw_eks.eks_node_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "us-w-center", Component = "data", Name = "usw-dsql-endpoint-sg" }
}

# MongoDB SG (US-W)
resource "aws_security_group" "sg_mongodb_usw" {
  name        = "usw-mongodb-sg"
  description = "Security group for MongoDB in US-W"
  vpc_id      = module.usw_center_vpc.vpc_id

  ingress {
    description     = "MongoDB from MSK Connect"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_msk_connect_usw.id]
  }

  ingress {
    description     = "MongoDB from EKS"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [module.usw_eks.eks_node_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "us-w-center", Component = "data", Name = "usw-mongodb-sg" }
}

# -----------------------------------------------------------------------------
# US-E Security Groups
# -----------------------------------------------------------------------------

# MSK Connect SG (US-E) - outbound only
resource "aws_security_group" "sg_msk_connect_use" {
  name        = "use-msk-connect-sg"
  description = "Security group for MSK Connect in US-E"
  vpc_id      = module.use_center_vpc.vpc_id
  provider    = aws.us_east_1

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "us-e-center", Component = "data", Name = "use-msk-connect-sg" }
}

# MSK SG (US-E)
resource "aws_security_group" "sg_msk_use" {
  name        = "use-msk-sg"
  description = "Security group for MSK in US-E"
  vpc_id      = module.use_center_vpc.vpc_id
  provider    = aws.us_east_1

  ingress {
    description     = "Kafka TLS from MSK Connect"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_msk_connect_use.id]
  }

  ingress {
    description = "Kafka TLS from OnPrem MM2 via TGW"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.onprem_vpc_cidr]
  }

  ingress {
    description     = "Kafka IAM auth from MSK Connect"
    from_port       = 9098
    to_port         = 9098
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_msk_connect_use.id]
  }

  ingress {
    description = "Kafka IAM auth from OnPrem MM2 via TGW"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.onprem_vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "us-e-center", Component = "data", Name = "use-msk-sg" }
}

# DSQL Endpoint SG (US-E)
resource "aws_security_group" "sg_dsql_endpoint_use" {
  name        = "use-dsql-endpoint-sg"
  description = "Security group for DSQL VPC endpoint in US-E"
  vpc_id      = module.use_center_vpc.vpc_id
  provider    = aws.us_east_1

  ingress {
    description     = "HTTPS from MSK Connect"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_msk_connect_use.id]
  }

  ingress {
    description     = "HTTPS from EKS"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.use_eks.eks_node_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "us-e-center", Component = "data", Name = "use-dsql-endpoint-sg" }
}

# MongoDB SG (US-E)
resource "aws_security_group" "sg_mongodb_use" {
  name        = "use-mongodb-sg"
  description = "Security group for MongoDB in US-E"
  vpc_id      = module.use_center_vpc.vpc_id
  provider    = aws.us_east_1

  ingress {
    description     = "MongoDB from MSK Connect"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_msk_connect_use.id]
  }

  ingress {
    description     = "MongoDB from EKS"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [module.use_eks.eks_node_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { VPC = "us-e-center", Component = "data", Name = "use-mongodb-sg" }
}

# =============================================================================
# TASK 12: OnPrem Data Layer - EC2 Instances
# =============================================================================

# -----------------------------------------------------------------------------
# OnPrem EC2 Database Instances (PostgreSQL, MongoDB, Kafka)
# -----------------------------------------------------------------------------

module "onprem_databases" {
  source   = "./modules/ec2-database"
  vpc_name = "Onprem"
  instances = {
    postgresql = {
      instance_type  = var.db_instance_type
      subnet_id      = module.onprem_vpc.data_subnet_ids[0]
      user_data_file = "user-data/postgresql.sh"
      sg_ids         = [aws_security_group.sg_postgresql.id]
      name           = "onprem-postgresql"
    }
    mongodb = {
      instance_type  = var.db_instance_type
      subnet_id      = module.onprem_vpc.data_subnet_ids[1]
      user_data_file = "user-data/mongodb.sh"
      sg_ids         = [aws_security_group.sg_mongodb.id]
      name           = "onprem-mongodb"
    }
    kafka-0 = {
      instance_type  = var.kafka_instance_type
      subnet_id      = module.onprem_vpc.data_subnet_ids[0]
      user_data_file = "user-data/kafka.sh"
      sg_ids         = [aws_security_group.sg_kafka.id]
      name           = "onprem-kafka-0"
    }
    kafka-1 = {
      instance_type  = var.kafka_instance_type
      subnet_id      = module.onprem_vpc.data_subnet_ids[0]
      user_data_file = "user-data/kafka.sh"
      sg_ids         = [aws_security_group.sg_kafka.id]
      name           = "onprem-kafka-1"
    }
    kafka-2 = {
      instance_type  = var.kafka_instance_type
      subnet_id      = module.onprem_vpc.data_subnet_ids[1]
      user_data_file = "user-data/kafka.sh"
      sg_ids         = [aws_security_group.sg_kafka.id]
      name           = "onprem-kafka-2"
    }
    kafka-3 = {
      instance_type  = var.kafka_instance_type
      subnet_id      = module.onprem_vpc.data_subnet_ids[1]
      user_data_file = "user-data/kafka.sh"
      sg_ids         = [aws_security_group.sg_kafka.id]
      name           = "onprem-kafka-3"
    }
  }
  tags = { VPC = "onprem", Component = "data" }
}
