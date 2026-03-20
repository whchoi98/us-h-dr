terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = var.vpc_name
  })
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-igw"
  })
}

################################################################################
# Public Subnets
################################################################################

resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                     = "${var.vpc_name}-public-${substr(var.availability_zones[count.index], -1, 1)}"
    "kubernetes.io/role/elb" = "1"
  })
}

################################################################################
# Public Route Table
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

################################################################################
# NAT Gateways (one per AZ)
################################################################################

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? length(var.public_subnets) : 0

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-nat-eip-${substr(var.availability_zones[count.index], -1, 1)}"
  })
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? length(var.public_subnets) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-nat-${substr(var.availability_zones[count.index], -1, 1)}"
  })

  depends_on = [aws_internet_gateway.this]
}

################################################################################
# Private Subnets
################################################################################

resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name                              = "${var.vpc_name}-private-${substr(var.availability_zones[count.index], -1, 1)}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

################################################################################
# Private Route Tables (one per AZ)
################################################################################

resource "aws_route_table" "private" {
  count = length(var.private_subnets)

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-rt-${substr(var.availability_zones[count.index], -1, 1)}"
  })
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? length(var.private_subnets) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

################################################################################
# Data Subnets
################################################################################

resource "aws_subnet" "data" {
  count = length(var.data_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.data_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-data-${substr(var.availability_zones[count.index], -1, 1)}"
  })
}

################################################################################
# Data Route Tables (one per AZ)
################################################################################

resource "aws_route_table" "data" {
  count = length(var.data_subnets)

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-data-rt-${substr(var.availability_zones[count.index], -1, 1)}"
  })
}

resource "aws_route" "data_nat" {
  count = var.enable_nat_gateway ? length(var.data_subnets) : 0

  route_table_id         = aws_route_table.data[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "data" {
  count = length(var.data_subnets)

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data[count.index].id
}

################################################################################
# TGW Attachment Subnets
################################################################################

resource "aws_subnet" "tgw" {
  count = length(var.tgw_subnets)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.tgw_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-tgw-${substr(var.availability_zones[count.index], -1, 1)}"
  })
}

################################################################################
# TGW Route Table (single shared, no default route)
################################################################################

resource "aws_route_table" "tgw" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.vpc_name}-tgw-rt"
  })
}

resource "aws_route_table_association" "tgw" {
  count = length(var.tgw_subnets)

  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw.id
}
