# Multi-Region DR Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build dual-IaC (Terraform + CDK) multi-region AWS infrastructure with 3 VPCs, EKS, and real-time database replication from OnPrem to AWS via Debezium CDC + MirrorMaker 2 + MSK + Aurora DSQL.

**Architecture:** 3 VPCs (OnPrem + US-W-CENTER in us-west-2, US-E-CENTER in us-east-1) connected via Transit Gateway with inter-region peering. CDC pipeline: Debezium → Kafka(EC2) → MirrorMaker 2 → MSK → MSK Connect → Aurora DSQL/MongoDB. CloudFront → ALB → EKS for all VPCs.

**Tech Stack:** Terraform >= 1.0, AWS Provider >= 5.0, AWS CDK 2.x (TypeScript), eksctl, Python 3 (test data)

**Spec:** `docs/superpowers/specs/2026-03-19-multi-region-dr-infra-design.md`

---

## Validation Pattern (referenced by all tasks)

All Terraform tasks follow this validation cycle:
```bash
cd /home/ec2-user/my-project/us-h-dr/terraform
terraform fmt -recursive
terraform validate
# Expected: Success! The configuration is valid.
```

All CDK tasks follow this validation cycle:
```bash
cd /home/ec2-user/my-project/us-h-dr/cdk
npx cdk synth --quiet
# Expected: Successfully synthesized to cdk.out
```

---

## Part 1: Terraform Foundation (Tasks 1-8)

### Task 1: Terraform Project Scaffold

**Files:**
- Create: `terraform/providers.tf`
- Create: `terraform/backend.tf`
- Create: `terraform/variables.tf`
- Create: `terraform/terraform.tfvars`
- Create: `terraform/outputs.tf`
- Create: `terraform/main.tf`

- [ ] **Step 1: Create providers.tf with multi-region support**

```hcl
# terraform/providers.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.primary_region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias  = "us_east_2"
  region = "us-east-2"
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}
```

- [ ] **Step 2: Create backend.tf**

```hcl
# terraform/backend.tf
terraform {
  backend "s3" {
    bucket         = "us-h-dr-terraform-state"
    key            = "multi-region-dr/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

- [ ] **Step 3: Create variables.tf with all project variables**

```hcl
# terraform/variables.tf
variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-west-2"
}

variable "dr_region" {
  description = "DR AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dr-lab"
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
  default     = "us-h-dr"
}

# VPC CIDRs
variable "onprem_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "usw_center_vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "use_center_vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}

# Subnet CIDRs - OnPrem
variable "onprem_public_subnets" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "onprem_private_subnets" {
  type    = list(string)
  default = ["10.0.16.0/20", "10.0.32.0/20"]
}

variable "onprem_data_subnets" {
  type    = list(string)
  default = ["10.0.48.0/23", "10.0.50.0/23"]
}

variable "onprem_tgw_subnets" {
  type    = list(string)
  default = ["10.0.252.0/24", "10.0.253.0/24"]
}

# Subnet CIDRs - US-W-CENTER
variable "usw_public_subnets" {
  type    = list(string)
  default = ["10.1.0.0/24", "10.1.1.0/24"]
}

variable "usw_private_subnets" {
  type    = list(string)
  default = ["10.1.16.0/20", "10.1.32.0/20"]
}

variable "usw_data_subnets" {
  type    = list(string)
  default = ["10.1.48.0/23", "10.1.50.0/23"]
}

variable "usw_tgw_subnets" {
  type    = list(string)
  default = ["10.1.252.0/24", "10.1.253.0/24"]
}

# Subnet CIDRs - US-E-CENTER
variable "use_public_subnets" {
  type    = list(string)
  default = ["10.2.0.0/24", "10.2.1.0/24"]
}

variable "use_private_subnets" {
  type    = list(string)
  default = ["10.2.16.0/20", "10.2.32.0/20"]
}

variable "use_data_subnets" {
  type    = list(string)
  default = ["10.2.48.0/23", "10.2.50.0/23"]
}

variable "use_tgw_subnets" {
  type    = list(string)
  default = ["10.2.252.0/24", "10.2.253.0/24"]
}

# EKS
variable "eks_version" {
  type    = string
  default = "1.33"
}

variable "eks_node_type" {
  type    = string
  default = "t4g.2xlarge"
}

variable "eks_node_count" {
  type    = number
  default = 8
}

# Data Layer
variable "db_instance_type" {
  type    = string
  default = "r7g.large"
}

variable "kafka_instance_type" {
  type    = string
  default = "m7g.xlarge"
}

variable "kafka_broker_count" {
  type    = number
  default = 4
}

variable "msk_instance_type" {
  type    = string
  default = "kafka.m7g.xlarge"
}

variable "msk_broker_count" {
  type    = number
  default = 4
}

# VSCode Server
variable "vscode_instance_type" {
  type    = string
  default = "m7g.xlarge"
}

variable "vscode_password" {
  type      = string
  sensitive = true
}
```

- [ ] **Step 4: Create terraform.tfvars**

```hcl
# terraform/terraform.tfvars
primary_region = "us-west-2"
dr_region      = "us-east-1"
environment    = "dr-lab"
project_name   = "us-h-dr"
```

- [ ] **Step 5: Create empty main.tf and outputs.tf placeholders**

```hcl
# terraform/main.tf
# Module instantiations will be added as modules are created.
# See deployment phases in spec Section 11.
```

```hcl
# terraform/outputs.tf
# Outputs will be added as modules are created.
```

- [ ] **Step 6: Initialize and validate**

```bash
cd /home/ec2-user/my-project/us-h-dr/terraform
terraform init -backend=false  # local state for now
terraform fmt -recursive
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 7: Commit**

```bash
git add terraform/
git commit -m "feat: scaffold Terraform project with multi-region providers and variables"
```

---

### Task 2: VPC Module (Reusable)

**Files:**
- Create: `terraform/modules/vpc/main.tf`
- Create: `terraform/modules/vpc/variables.tf`
- Create: `terraform/modules/vpc/outputs.tf`

- [ ] **Step 1: Create modules/vpc/variables.tf**

```hcl
# terraform/modules/vpc/variables.tf
variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet CIDRs"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of private subnet CIDRs"
  type        = list(string)
}

variable "data_subnets" {
  description = "List of data subnet CIDRs"
  type        = list(string)
}

variable "tgw_subnets" {
  description = "List of TGW attachment subnet CIDRs"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of AZs"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway per AZ"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Create modules/vpc/main.tf**

Write complete VPC module with:
- VPC resource with DNS support/hostnames enabled
- IGW
- 4 subnet tiers x 2 AZs (public, private, data, tgw_attachment) using `count`
- NAT Gateway per AZ in public subnets (with EIP)
- Route tables: public (→ IGW), private (→ NAT GW), data (→ NAT GW), tgw_attachment (no default route)
- Route table associations
- Tags following spec Section 12

Key patterns from `aws_lab_infra` reference:
- Use `count = length(var.public_subnets)` for subnet iteration
- Separate route tables per tier
- EKS subnet tags: `kubernetes.io/role/internal-elb = 1` on private subnets

```hcl
# terraform/modules/vpc/main.tf
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(var.tags, { Name = var.vpc_name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.vpc_name}-igw" })
}

# --- Public Subnets ---
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-public-${substr(var.availability_zones[count.index], -1, 1)}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.vpc_name}-public-rt" })
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- NAT Gateways (one per AZ) ---
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? length(var.public_subnets) : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.vpc_name}-nat-eip-${substr(var.availability_zones[count.index], -1, 1)}" })
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? length(var.public_subnets) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.tags, { Name = "${var.vpc_name}-natgw-${substr(var.availability_zones[count.index], -1, 1)}" })
  depends_on    = [aws_internet_gateway.this]
}

# --- Private Subnets ---
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-private-${substr(var.availability_zones[count.index], -1, 1)}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnets)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.vpc_name}-private-rt-${substr(var.availability_zones[count.index], -1, 1)}" })
}

resource "aws_route" "private_nat" {
  count                  = var.enable_nat_gateway ? length(var.private_subnets) : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# --- Data Subnets ---
resource "aws_subnet" "data" {
  count             = length(var.data_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.data_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-data-${substr(var.availability_zones[count.index], -1, 1)}"
  })
}

resource "aws_route_table" "data" {
  count  = length(var.data_subnets)
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.vpc_name}-data-rt-${substr(var.availability_zones[count.index], -1, 1)}" })
}

resource "aws_route" "data_nat" {
  count                  = var.enable_nat_gateway ? length(var.data_subnets) : 0
  route_table_id         = aws_route_table.data[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "data" {
  count          = length(var.data_subnets)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data[count.index].id
}

# --- TGW Attachment Subnets ---
resource "aws_subnet" "tgw" {
  count             = length(var.tgw_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.tgw_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-tgw-${substr(var.availability_zones[count.index], -1, 1)}"
  })
}

resource "aws_route_table" "tgw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.vpc_name}-tgw-rt" })
}

resource "aws_route_table_association" "tgw" {
  count          = length(var.tgw_subnets)
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw.id
}
```

- [ ] **Step 3: Create modules/vpc/outputs.tf**

```hcl
# terraform/modules/vpc/outputs.tf
output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "data_subnet_ids" {
  value = aws_subnet.data[*].id
}

output "tgw_subnet_ids" {
  value = aws_subnet.tgw[*].id
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}

output "private_route_table_ids" {
  value = aws_route_table.private[*].id
}

output "data_route_table_ids" {
  value = aws_route_table.data[*].id
}
```

- [ ] **Step 4: Validate module syntax**

```bash
cd /home/ec2-user/my-project/us-h-dr/terraform
terraform fmt -recursive
terraform validate
```

- [ ] **Step 5: Commit**

```bash
git add terraform/modules/vpc/
git commit -m "feat: add reusable VPC module with 4 subnet tiers and NAT GW"
```

---

### Task 3: Instantiate 3 VPCs in main.tf

**Files:**
- Modify: `terraform/main.tf`

- [ ] **Step 1: Add 3 VPC module calls to main.tf**

```hcl
# terraform/main.tf

data "aws_availability_zones" "usw2" {
  state = "available"
}

data "aws_availability_zones" "use1" {
  provider = aws.us_east_1
  state    = "available"
}

# --- OnPrem VPC (us-west-2) ---
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

# --- US-W-CENTER VPC (us-west-2) ---
module "usw_center_vpc" {
  source             = "./modules/vpc"
  vpc_name           = "US-W-CENTER"
  vpc_cidr           = var.usw_center_vpc_cidr
  public_subnets     = var.usw_public_subnets
  private_subnets    = var.usw_private_subnets
  data_subnets       = var.usw_data_subnets
  tgw_subnets        = var.usw_tgw_subnets
  availability_zones = slice(data.aws_availability_zones.usw2.names, 0, 2)
  tags               = { VPC = "us-w-center", Component = "network" }
}

# --- US-E-CENTER VPC (us-east-1) ---
module "use_center_vpc" {
  source             = "./modules/vpc"
  vpc_name           = "US-E-CENTER"
  vpc_cidr           = var.use_center_vpc_cidr
  public_subnets     = var.use_public_subnets
  private_subnets    = var.use_private_subnets
  data_subnets       = var.use_data_subnets
  tgw_subnets        = var.use_tgw_subnets
  availability_zones = slice(data.aws_availability_zones.use1.names, 0, 2)
  tags               = { VPC = "us-e-center", Component = "network" }

  providers = {
    aws = aws.us_east_1
  }
}
```

- [ ] **Step 2: Validate**

Run validation pattern. Expected: `Success!`

- [ ] **Step 3: Commit**

```bash
git add terraform/main.tf
git commit -m "feat: instantiate 3 VPCs (OnPrem, US-W-CENTER, US-E-CENTER)"
```

---

### Task 4: VPC Endpoints Module

**Files:**
- Create: `terraform/modules/vpc-endpoints/main.tf`
- Create: `terraform/modules/vpc-endpoints/variables.tf`
- Create: `terraform/modules/vpc-endpoints/outputs.tf`

- [ ] **Step 1: Create module with SSM + optional DSQL endpoints**

```hcl
# terraform/modules/vpc-endpoints/variables.tf
variable "vpc_id" { type = string }
variable "vpc_name" { type = string }
variable "region" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "enable_dsql_endpoint" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
```

```hcl
# terraform/modules/vpc-endpoints/main.tf
resource "aws_security_group" "vpce" {
  name_prefix = "${var.vpc_name}-vpce-"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.vpc_name}-vpce-sg" })
}

locals {
  ssm_services = [
    "com.amazonaws.${var.region}.ssm",
    "com.amazonaws.${var.region}.ssmmessages",
    "com.amazonaws.${var.region}.ec2messages",
  ]
  dsql_services = var.enable_dsql_endpoint ? ["com.amazonaws.${var.region}.dsql"] : []
  all_services  = concat(local.ssm_services, local.dsql_services)
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(local.all_services)
  vpc_id              = var.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  tags = merge(var.tags, {
    Name = "${var.vpc_name}-${split(".", each.value)[length(split(".", each.value)) - 1]}-endpoint"
  })
}
```

```hcl
# terraform/modules/vpc-endpoints/outputs.tf
output "endpoint_ids" {
  value = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "vpce_security_group_id" {
  value = aws_security_group.vpce.id
}
```

- [ ] **Step 2: Add to main.tf**

```hcl
# Add to terraform/main.tf
module "onprem_vpc_endpoints" {
  source               = "./modules/vpc-endpoints"
  vpc_id               = module.onprem_vpc.vpc_id
  vpc_name             = "Onprem"
  region               = var.primary_region
  private_subnet_ids   = module.onprem_vpc.private_subnet_ids
  enable_dsql_endpoint = false
  tags                 = { VPC = "onprem", Component = "network" }
}

module "usw_vpc_endpoints" {
  source               = "./modules/vpc-endpoints"
  vpc_id               = module.usw_center_vpc.vpc_id
  vpc_name             = "US-W-CENTER"
  region               = var.primary_region
  private_subnet_ids   = module.usw_center_vpc.private_subnet_ids
  enable_dsql_endpoint = true
  tags                 = { VPC = "us-w-center", Component = "network" }
}

module "use_vpc_endpoints" {
  source               = "./modules/vpc-endpoints"
  vpc_id               = module.use_center_vpc.vpc_id
  vpc_name             = "US-E-CENTER"
  region               = var.dr_region
  private_subnet_ids   = module.use_center_vpc.private_subnet_ids
  enable_dsql_endpoint = true
  tags                 = { VPC = "us-e-center", Component = "network" }
  providers            = { aws = aws.us_east_1 }
}
```

- [ ] **Step 3: Validate and commit**

```bash
terraform fmt -recursive && terraform validate
git add terraform/modules/vpc-endpoints/ terraform/main.tf
git commit -m "feat: add VPC endpoints module (SSM + DSQL PrivateLink)"
```

---

### Task 5: Transit Gateway Module (us-west-2)

**Files:**
- Create: `terraform/modules/tgw/main.tf`
- Create: `terraform/modules/tgw/variables.tf`
- Create: `terraform/modules/tgw/outputs.tf`

- [ ] **Step 1: Create TGW module**

```hcl
# terraform/modules/tgw/variables.tf
variable "name" { type = string }
variable "amazon_side_asn" { type = number }
variable "vpc_attachments" {
  description = "Map of VPC attachments"
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
    vpc_cidr   = string
  }))
}
variable "tags" {
  type    = map(string)
  default = {}
}
```

```hcl
# terraform/modules/tgw/main.tf
resource "aws_ec2_transit_gateway" "this" {
  amazon_side_asn                 = var.amazon_side_asn
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  tags = merge(var.tags, { Name = var.name })
}

resource "aws_ec2_transit_gateway_route_table" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  tags = merge(var.tags, { Name = "${var.name}-rt" })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each           = var.vpc_attachments
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids
  tags = merge(var.tags, { Name = "${var.name}-${each.key}-attach" })
}

resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each                       = var.vpc_attachments
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

resource "aws_ec2_transit_gateway_route" "vpc_routes" {
  for_each                       = var.vpc_attachments
  destination_cidr_block         = each.value.vpc_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}
```

```hcl
# terraform/modules/tgw/outputs.tf
output "tgw_id" {
  value = aws_ec2_transit_gateway.this.id
}

output "tgw_route_table_id" {
  value = aws_ec2_transit_gateway_route_table.this.id
}

output "tgw_attachment_ids" {
  value = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}
```

- [ ] **Step 2: Add TGW-West to main.tf + VPC route table entries for TGW**

```hcl
# Add to terraform/main.tf
module "tgw_west" {
  source          = "./modules/tgw"
  name            = "dr-lab-tgw-west"
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
  name            = "dr-lab-tgw-east"
  amazon_side_asn = 65001
  vpc_attachments = {
    use-center = {
      vpc_id     = module.use_center_vpc.vpc_id
      subnet_ids = module.use_center_vpc.tgw_subnet_ids
      vpc_cidr   = var.use_center_vpc_cidr
    }
  }
  tags      = { Component = "network" }
  providers = { aws = aws.us_east_1 }
}
```

Also add TGW routes to VPC private/data route tables (cross-VPC routing):
- OnPrem private/data RT: 10.1.0.0/16 → TGW, 10.2.0.0/16 → TGW
- US-W private/data RT: 10.0.0.0/16 → TGW, 10.2.0.0/16 → TGW
- US-E private/data RT: 10.0.0.0/16 → TGW, 10.1.0.0/16 → TGW

Add `aws_route` resources for each cross-VPC route in main.tf.

- [ ] **Step 3: Validate and commit**

```bash
terraform fmt -recursive && terraform validate
git add terraform/modules/tgw/ terraform/main.tf
git commit -m "feat: add Transit Gateway module with West/East TGWs and VPC routes"
```

---

### Task 6: TGW Inter-Region Peering Module

**Files:**
- Create: `terraform/modules/tgw-peering/main.tf`
- Create: `terraform/modules/tgw-peering/variables.tf`
- Create: `terraform/modules/tgw-peering/outputs.tf`

- [ ] **Step 1: Create peering module**

```hcl
# terraform/modules/tgw-peering/variables.tf
variable "requester_tgw_id" { type = string }
variable "requester_tgw_route_table_id" { type = string }
variable "requester_region" { type = string }
variable "accepter_tgw_id" { type = string }
variable "accepter_tgw_route_table_id" { type = string }
variable "accepter_region" { type = string }
variable "requester_routes" {
  description = "CIDRs to route via peering from requester side"
  type        = list(string)
}
variable "accepter_routes" {
  description = "CIDRs to route via peering from accepter side"
  type        = list(string)
}
variable "tags" {
  type    = map(string)
  default = {}
}
```

```hcl
# terraform/modules/tgw-peering/main.tf
resource "aws_ec2_transit_gateway_peering_attachment" "this" {
  transit_gateway_id      = var.requester_tgw_id
  peer_transit_gateway_id = var.accepter_tgw_id
  peer_region             = var.accepter_region
  tags = merge(var.tags, { Name = "tgw-peering-${var.requester_region}-${var.accepter_region}" })
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "this" {
  provider                      = aws.accepter
  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.this.id
  tags = merge(var.tags, { Name = "tgw-peering-accept-${var.requester_region}-${var.accepter_region}" })
}

# Requester-side routes (us-west-2 → us-east-1 CIDRs)
resource "aws_ec2_transit_gateway_route" "requester" {
  count                          = length(var.requester_routes)
  destination_cidr_block         = var.requester_routes[count.index]
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this.id
  transit_gateway_route_table_id = var.requester_tgw_route_table_id
}

# Accepter-side routes (us-east-1 → us-west-2 CIDRs)
resource "aws_ec2_transit_gateway_route" "accepter" {
  provider                       = aws.accepter
  count                          = length(var.accepter_routes)
  destination_cidr_block         = var.accepter_routes[count.index]
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.this.id
  transit_gateway_route_table_id = var.accepter_tgw_route_table_id
}
```

- [ ] **Step 2: Add peering to main.tf**

```hcl
module "tgw_peering" {
  source                       = "./modules/tgw-peering"
  requester_tgw_id             = module.tgw_west.tgw_id
  requester_tgw_route_table_id = module.tgw_west.tgw_route_table_id
  requester_region             = var.primary_region
  accepter_tgw_id              = module.tgw_east.tgw_id
  accepter_tgw_route_table_id  = module.tgw_east.tgw_route_table_id
  accepter_region              = var.dr_region
  requester_routes             = [var.use_center_vpc_cidr]
  accepter_routes              = [var.onprem_vpc_cidr, var.usw_center_vpc_cidr]
  tags                         = { Component = "network" }
  providers = {
    aws          = aws
    aws.accepter = aws.us_east_1
  }
}
```

- [ ] **Step 3: Validate and commit**

```bash
terraform fmt -recursive && terraform validate
git add terraform/modules/tgw-peering/ terraform/main.tf
git commit -m "feat: add TGW inter-region peering (us-west-2 <-> us-east-1)"
```

---

### Task 7: CloudFront + ALB Module

**Files:**
- Create: `terraform/modules/cloudfront-alb/main.tf`
- Create: `terraform/modules/cloudfront-alb/variables.tf`
- Create: `terraform/modules/cloudfront-alb/outputs.tf`

- [ ] **Step 1: Create module with ALB + CloudFront distribution + custom header protection**

Key resources:
- `aws_lb` (ALB in public subnets)
- `aws_lb_listener` (HTTP:80 with fixed-response 403 default + header-match rule)
- `aws_security_group` (ALB SG: CloudFront prefix list ingress only)
- `aws_cloudfront_distribution` (HTTPS → ALB origin, custom header injection)
- Use `data "aws_ec2_managed_prefix_list"` for `com.amazonaws.global.cloudfront.origin-facing`
- Custom header: `X-Custom-Secret` = `${var.stack_name}-secret-${data.aws_caller_identity.current.account_id}`

Reference: `aws_lab_infra/shared/03.deploy-cloudfront-protection.sh` pattern

> **ALB → EKS wiring:** ALB target group is registered via AWS Load Balancer Controller in EKS.
> When LBC addon is installed (Task 9), Kubernetes `Ingress` resources automatically create ALB target groups
> pointing to EKS pods. The ALB created here serves as the initial ALB; LBC will manage target group bindings.

- [ ] **Step 2: Add 3 CloudFront+ALB instances to main.tf (OnPrem, US-W, US-E)**

- [ ] **Step 3: Validate and commit**

```bash
git commit -m "feat: add CloudFront + ALB module with custom header protection"
```

---

### Task 8: Route 53 Failover

**Files:**
- Create: `terraform/modules/route53-failover/main.tf`
- Create: `terraform/modules/route53-failover/variables.tf`
- Create: `terraform/modules/route53-failover/outputs.tf`

- [ ] **Step 1: Create module with hosted zone, health checks, failover records**

Key resources:
- `aws_route53_zone` (or use existing)
- `aws_route53_health_check` (ALB endpoints)
- `aws_route53_record` (failover: PRIMARY → US-W CF, SECONDARY → US-E CF)

- [ ] **Step 2: Add to main.tf, validate, and commit**

```bash
git commit -m "feat: add Route 53 failover routing for DR"
```

---

## Part 2: Terraform Compute (Tasks 9-11)

### Task 9: EKS Module (eksctl wrapper)

**Files:**
- Create: `terraform/modules/eks/main.tf`
- Create: `terraform/modules/eks/variables.tf`
- Create: `terraform/modules/eks/outputs.tf`
- Create: `terraform/modules/eks/eksctl-config.yaml.tpl`

- [ ] **Step 1: Create EKS module**

This module creates:
- IAM roles for EKS (cluster role, node role, pod identity agent)
- Security groups for EKS nodes
- `local_file` resource to render `eksctl-config.yaml.tpl` with VPC/subnet IDs
- No EKS cluster itself — that's created via eksctl script

```hcl
# terraform/modules/eks/eksctl-config.yaml.tpl
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${cluster_name}
  region: ${region}
  version: "${eks_version}"
vpc:
  id: "${vpc_id}"
  subnets:
    private:
      ${az_a}:
        id: "${private_subnet_a}"
      ${az_b}:
        id: "${private_subnet_b}"
managedNodeGroups:
  - name: ng-main
    instanceType: ${node_type}
    desiredCapacity: ${node_count}
    minSize: ${node_count}
    maxSize: ${node_count}
    volumeSize: 100
    volumeType: gp3
    amiFamily: AmazonLinux2023
addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver
  - name: aws-efs-csi-driver
  - name: eks-pod-identity-agent
  - name: amazon-cloudwatch-observability
  - name: aws-load-balancer-controller
    version: v3.1.0
  - name: karpenter
    version: v1.9.0
```

- [ ] **Step 2: Add 3 EKS module instances (OnPrem, US-W, US-E)**

- [ ] **Step 3: Validate and commit**

```bash
git commit -m "feat: add EKS module with eksctl config template"
```

---

### Task 10: VSCode Server Module

**Files:**
- Create: `terraform/modules/vscode-server/main.tf`
- Create: `terraform/modules/vscode-server/variables.tf`
- Create: `terraform/modules/vscode-server/outputs.tf`
- Create: `terraform/modules/vscode-server/user-data.sh`

- [ ] **Step 1: Create user-data.sh**

Reference: `ec2_vscode/infra-cdk/lib/vscode-stack.ts` UserData pattern.

Install: code-server v4.110.0, Docker, Node.js 20, Python 3, AWS CLI v2, eksctl, kubectl, helm, Claude Code.
Configure: systemd service for code-server on port 8888.

- [ ] **Step 2: Create module with EC2, IAM role, security group**

Key resources:
- `aws_instance` (m7g.xlarge, AL2023 ARM64, private subnet, 100GB gp3 EBS encrypted)
- `aws_iam_role` + `aws_iam_instance_profile` (SSM + CloudWatch)
- `aws_security_group` (TCP 8888 from ALB SG)

- [ ] **Step 3: Add to main.tf (OnPrem VPC only)**

- [ ] **Step 4: Validate and commit**

```bash
git commit -m "feat: add VSCode Server on EC2 module (OnPrem VPC)"
```

---

### Task 11: Shared Scripts - EKS and Prerequisites

**Files:**
- Create: `shared/scripts/check-prerequisites.sh`
- Create: `shared/scripts/eks-setup-env.sh`
- Create: `shared/scripts/eks-create-cluster.sh`
- Create: `shared/configs/eksctl-cluster-config.yaml`

- [ ] **Step 1: Create check-prerequisites.sh**

Reference: `aws_lab_infra/shared/00.check-prerequisites.sh`
Check: aws, eksctl, kubectl, helm, jq, python3, docker

- [ ] **Step 2: Create EKS scripts**

`eks-setup-env.sh`: Source AWS account info, set cluster variables.
`eks-create-cluster.sh`: Run `eksctl create cluster -f <config>` for each VPC.

- [ ] **Step 3: Create eksctl cluster config**

Use rendered template from Task 9 or standalone YAML.

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: add shared scripts for prerequisites and EKS cluster creation"
```

---

## Part 3: Terraform Data Layer (Tasks 12-18)

### Task 12: EC2 Database Module (OnPrem)

**Files:**
- Create: `terraform/modules/ec2-database/main.tf`
- Create: `terraform/modules/ec2-database/variables.tf`
- Create: `terraform/modules/ec2-database/outputs.tf`
- Create: `terraform/modules/ec2-database/user-data/postgresql.sh`
- Create: `terraform/modules/ec2-database/user-data/mongodb.sh`
- Create: `terraform/modules/ec2-database/user-data/kafka.sh`
- Create: `terraform/modules/ec2-database/user-data/mirrormaker2.sh`

- [ ] **Step 1: Create user-data scripts for each service**

`postgresql.sh`: Install PostgreSQL 16, configure WAL logical replication (`wal_level=logical`), create CDC user.
`mongodb.sh`: Install MongoDB 7.0, enable change streams (replica set init).
`kafka.sh`: Install Apache Kafka 3.7, configure broker.id, listeners, inter-broker TLS.
`mirrormaker2.sh`: Install Kafka (for MM2 tool), configure source/target clusters, SASL/IAM for MSK.

- [ ] **Step 2: Create flexible ec2-database module**

Module accepts a list of instances with per-instance config (type, user-data, subnet, SG):

```hcl
variable "instances" {
  type = map(object({
    instance_type = string
    subnet_id     = string
    user_data     = string
    sg_ids        = list(string)
    name          = string
  }))
}
```

Creates: `aws_instance`, `aws_iam_role`, `aws_iam_instance_profile` per instance.

- [ ] **Step 3: Create security groups for OnPrem data layer in main.tf**

SGs per spec Section 6.1: sg-postgresql, sg-mongodb, sg-kafka, sg-debezium, sg-mm2.

- [ ] **Step 4: Add OnPrem data layer instances to main.tf**

PostgreSQL (Data-a), MongoDB (Data-b), Kafka ×4 (2+2 across AZs).
Note: Debezium and MirrorMaker 2 are deployed via separate modules (Tasks 13, see `terraform/modules/debezium/`).

- [ ] **Step 5: Validate and commit**

```bash
git commit -m "feat: add EC2 database module with OnPrem data layer instances"
```

---

### Task 13: Debezium Module (OnPrem)

**Files:**
- Create: `terraform/modules/debezium/main.tf`
- Create: `terraform/modules/debezium/variables.tf`
- Create: `terraform/modules/debezium/outputs.tf`
- Create: `terraform/modules/debezium/user-data.sh`
- Create: `terraform/modules/debezium/connector-configs/postgres-source.json`
- Create: `terraform/modules/debezium/connector-configs/mongodb-source.json`

- [ ] **Step 1: Create Debezium user-data and connector configs**

`user-data.sh`: Install Java 17, Kafka Connect, Debezium PostgreSQL + MongoDB connectors.
`postgres-source.json`: Debezium PostgreSQL source connector config (WAL, all tables).
`mongodb-source.json`: Debezium MongoDB source connector config (change streams, all collections).

- [ ] **Step 2: Create module (EC2 + configs as S3 or local provisioner)**

- [ ] **Step 3: Add to main.tf, validate, commit**

```bash
git commit -m "feat: add Debezium Kafka Connect module with connector configs"
```

---

### Task 14: Amazon MSK Module

**Files:**
- Create: `terraform/modules/msk/main.tf`
- Create: `terraform/modules/msk/variables.tf`
- Create: `terraform/modules/msk/outputs.tf`

- [ ] **Step 1: Create MSK module**

Key resources:
- `aws_msk_cluster` (4 brokers, kafka.m7g.xlarge, TLS+IAM auth, KMS encryption)
- `aws_msk_configuration` (auto.create.topics.enable=true, default.replication.factor=3)
- `aws_security_group` for MSK (ports 9094 TLS, 9098 IAM only — no 9092 PLAINTEXT)
- `aws_cloudwatch_log_group` for broker logs

```hcl
variable "cluster_name" { type = string }
variable "kafka_version" {
  type    = string
  default = "3.7.x.kraft"
}
variable "broker_instance_type" { type = string }
variable "number_of_broker_nodes" { type = number }
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "tags" {
  type    = map(string)
  default = {}
}
```

- [ ] **Step 2: Create security groups for MSK, MSK Connect, and DSQL endpoint in main.tf**

Create in main.tf for US-W-CENTER and US-E-CENTER VPCs:
- `sg-msk-usw` / `sg-msk-use`: TCP 9094(TLS), 9098(IAM) from MM2 SG (via TGW), MSK Connect SG
- `sg-msk-connect-usw` / `sg-msk-connect-use`: Outbound only to MSK, DSQL endpoint, MongoDB
- `sg-dsql-endpoint` / `sg-dsql-endpoint-use`: TCP 443 from MSK Connect SG, EKS SG
- `sg-mongodb-usw` / `sg-mongodb-use`: TCP 27017 from MSK Connect SG, EKS SG

These SGs are referenced by MSK, MSK Connect, DSQL endpoint, and MongoDB modules.

- [ ] **Step 3: Add MSK instances for US-W and US-E to main.tf**

```hcl
module "msk_usw" {
  source                 = "./modules/msk"
  cluster_name           = "dr-lab-msk-usw"
  broker_instance_type   = var.msk_instance_type
  number_of_broker_nodes = var.msk_broker_count
  subnet_ids             = module.usw_center_vpc.data_subnet_ids
  security_group_ids     = [aws_security_group.msk_usw.id]
  tags                   = { VPC = "us-w-center", Component = "data" }
}

module "msk_use" {
  source                 = "./modules/msk"
  cluster_name           = "dr-lab-msk-use"
  broker_instance_type   = var.msk_instance_type
  number_of_broker_nodes = var.msk_broker_count
  subnet_ids             = module.use_center_vpc.data_subnet_ids
  security_group_ids     = [aws_security_group.msk_use.id]
  tags                   = { VPC = "us-e-center", Component = "data" }
  providers              = { aws = aws.us_east_1 }
}
```

- [ ] **Step 3: Validate and commit**

```bash
git commit -m "feat: add Amazon MSK module for US-W and US-E clusters"
```

---

### Task 15: Aurora DSQL Module

**Files:**
- Create: `terraform/modules/aurora-dsql/main.tf`
- Create: `terraform/modules/aurora-dsql/variables.tf`
- Create: `terraform/modules/aurora-dsql/outputs.tf`

- [ ] **Step 1: Create DSQL module**

Key resources:
- `aws_dsql_cluster` (primary in us-west-2)
- `aws_dsql_cluster` (linked in us-east-1, multi-region linked to primary)
- Witness region: us-east-2

Note: Aurora DSQL uses `aws_dsql_cluster` resource. Multi-region configuration requires specifying linked clusters.
The module uses the `aws.us_east_1` provider for the linked cluster and `aws.us_east_2` provider for the witness region (all 3 providers from Task 1).

```hcl
variable "primary_cluster_name" { type = string }
variable "linked_cluster_name" { type = string }
variable "witness_region" {
  type    = string
  default = "us-east-2"
}
variable "tags" {
  type    = map(string)
  default = {}
}
```

Pass providers when calling the module:
```hcl
module "aurora_dsql" {
  source = "./modules/aurora-dsql"
  # ...
  providers = {
    aws           = aws            # us-west-2 (primary)
    aws.linked    = aws.us_east_1  # us-east-1 (linked)
    aws.witness   = aws.us_east_2  # us-east-2 (witness)
  }
}
```

- [ ] **Step 2: Add to main.tf**

- [ ] **Step 3: Validate and commit**

```bash
git commit -m "feat: add Aurora DSQL multi-region module (Primary + Linked + Witness)"
```

---

### Task 16: MongoDB EC2 for US-W and US-E

**Files:**
- Modify: `terraform/main.tf`

- [ ] **Step 1: Reuse ec2-database module for US-W and US-E MongoDB instances**

Add MongoDB EC2 instances in US-W-CENTER and US-E-CENTER data subnets.
Security groups: sg-mongodb-usw, sg-mongodb-use (per spec Section 6.1).

- [ ] **Step 2: Validate and commit**

```bash
git commit -m "feat: add MongoDB EC2 instances for US-W and US-E VPCs"
```

---

### Task 17: MSK Replicator Module (US-W → US-E)

**Files:**
- Create: `terraform/modules/msk-replicator/main.tf`
- Create: `terraform/modules/msk-replicator/variables.tf`
- Create: `terraform/modules/msk-replicator/outputs.tf`

> **Note:** MSK Replicator is deployed BEFORE MSK Connect sinks, per spec Section 11 (step 27 before 28-30). This ensures data flows from US-W MSK to US-E MSK before sinks consume from US-E topics.

- [ ] **Step 1: Create MSK Replicator module**

Key resources:
- `aws_msk_replicator` (source: US-W MSK, target: US-E MSK)
- IAM role for replicator
- Topic replication pattern: `source\..*`

- [ ] **Step 2: Add to main.tf**

- [ ] **Step 3: Validate and commit**

```bash
git commit -m "feat: add MSK Replicator module (US-W MSK -> US-E MSK)"
```

---

### Task 18: MSK Connect Module

**Files:**
- Create: `terraform/modules/msk-connect/main.tf`
- Create: `terraform/modules/msk-connect/variables.tf`
- Create: `terraform/modules/msk-connect/outputs.tf`
- Create: `terraform/modules/msk-connect/connector-configs/confluent-jdbc-sink.json`
- Create: `terraform/modules/msk-connect/connector-configs/mongodb-sink.json`

- [ ] **Step 1: Create MSK Connect module**

Key resources:
- `aws_mskconnect_custom_plugin` (S3 bucket with Confluent JDBC + MongoDB connector JARs)
- `aws_mskconnect_connector` (JDBC Sink for DSQL, MongoDB Sink for MongoDB EC2)
- `aws_iam_role` for MSK Connect execution (MSK + DSQL + S3 access)
- `aws_s3_bucket` for connector plugins

Connector configs reference spec Section 4.2:
- JDBC Sink: DSQL IAM auth, PrivateLink endpoint, upsert mode, retry config
- MongoDB Sink: upsert mode, document._id based

- [ ] **Step 2: Add MSK Connect for US-W (JDBC Sink + MongoDB Sink)**

- [ ] **Step 3: Add MSK Connect for US-E (MongoDB Sink only)**

- [ ] **Step 4: Validate and commit**

```bash
git commit -m "feat: add MSK Connect module with JDBC and MongoDB sink connectors"
```

---

## Part 4: Terraform Monitoring & Remaining (Tasks 19-20)

### Task 19: Monitoring Module

**Files:**
- Create: `terraform/modules/monitoring/main.tf`
- Create: `terraform/modules/monitoring/variables.tf`
- Create: `terraform/modules/monitoring/outputs.tf`

- [ ] **Step 1: Create monitoring module**

Key resources per spec Section 7:
- `aws_sns_topic` per region (`dr-lab-alerts-usw2`, `dr-lab-alerts-use1`)
- `aws_cloudwatch_metric_alarm` for MSK, MSK Connect, DSQL, EKS
- `aws_cloudwatch_log_group` for MSK, MSK Connect, Debezium
- `aws_cloudwatch_dashboard` (optional summary)

- [ ] **Step 2: Add for both regions**

- [ ] **Step 3: Validate and commit**

```bash
git commit -m "feat: add monitoring module with CloudWatch alarms and SNS topics"
```

---

## Part 5: Shared Scripts & Test Data (Tasks 20-23)

### Task 20: Debezium Setup Script

**Files:**
- Create: `shared/scripts/setup-debezium.sh`
- Create: `shared/configs/debezium-postgres-source.json`
- Create: `shared/configs/debezium-mongodb-source.json`

- [ ] **Step 1: Create connector config JSONs**

```json
// shared/configs/debezium-postgres-source.json
{
  "name": "postgres-source",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "${POSTGRES_HOST}",
    "database.port": "5432",
    "database.user": "debezium",
    "database.password": "${POSTGRES_PASSWORD}",
    "database.dbname": "ecommerce",
    "database.server.name": "dbserver1",
    "plugin.name": "pgoutput",
    "slot.name": "debezium_slot",
    "publication.name": "dbz_publication",
    "table.include.list": "public.users,public.products,public.orders,public.order_items,public.reviews",
    "topic.prefix": "dbserver1",
    "schema.history.internal.kafka.bootstrap.servers": "${KAFKA_BROKERS}",
    "schema.history.internal.kafka.topic": "schema-changes.ecommerce"
  }
}
```

```json
// shared/configs/debezium-mongodb-source.json
{
  "name": "mongodb-source",
  "config": {
    "connector.class": "io.debezium.connector.mongodb.MongoDbConnector",
    "mongodb.connection.string": "mongodb://${MONGO_HOST}:27017",
    "topic.prefix": "mongo",
    "collection.include.list": "ecommerce.users,ecommerce.products,ecommerce.orders,ecommerce.reviews,ecommerce.sessions",
    "capture.mode": "change_streams_update_full"
  }
}
```

- [ ] **Step 2: Create setup-debezium.sh**

Script to register connectors via Kafka Connect REST API (port 8083).

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add Debezium connector configs and setup script"
```

---

### Task 21: MirrorMaker 2 Setup Script

**Files:**
- Create: `shared/scripts/setup-mirrormaker2.sh`
- Create: `shared/configs/mirrormaker2.properties`

- [ ] **Step 1: Create MM2 properties**

```properties
# shared/configs/mirrormaker2.properties
clusters = source, target
source.bootstrap.servers = localhost:9092
target.bootstrap.servers = ${MSK_BOOTSTRAP_SERVERS}
target.security.protocol = SASL_SSL
target.sasl.mechanism = AWS_MSK_IAM
target.sasl.jaas.config = software.amazon.msk.auth.iam.IAMLoginModule required;
target.sasl.client.callback.handler.class = software.amazon.msk.auth.iam.IAMClientCallbackHandler

source->target.enabled = true
source->target.topics = dbserver1\\.public\\..*,mongo\\.ecommerce\\..*
source->target.groups = .*

replication.factor = 3
checkpoints.topic.replication.factor = 3
heartbeats.topic.replication.factor = 3
offset-syncs.topic.replication.factor = 3
offset.storage.replication.factor = 3
status.storage.replication.factor = 3
config.storage.replication.factor = 3
```

- [ ] **Step 2: Create setup script**

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add MirrorMaker 2 config and setup script"
```

---

### Task 22: MSK Connect Sink Connector Configs

**Files:**
- Create: `shared/configs/confluent-jdbc-sink.json`
- Create: `shared/configs/mongodb-sink.json`

- [ ] **Step 1: Create JDBC Sink config for Aurora DSQL**

```json
{
  "name": "dsql-jdbc-sink",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
    "connection.url": "jdbc:aws-dsql://${DSQL_ENDPOINT}:5432/postgres",
    "connection.provider": "com.example.DsqlIamConnectionProvider",
    "topics.regex": "source\\.dbserver1\\.public\\..*",
    "insert.mode": "upsert",
    "pk.mode": "record_key",
    "auto.create": "true",
    "auto.evolve": "true",
    "errors.retry.timeout": "300000",
    "errors.retry.delay.max.ms": "60000",
    "errors.tolerance": "all",
    "errors.deadletterqueue.topic.name": "dlq-dsql-sink",
    "errors.deadletterqueue.topic.replication.factor": "3",
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "true"
  }
}
```

- [ ] **Step 2: Create MongoDB Sink config**

```json
{
  "name": "mongodb-sink",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
    "connection.uri": "mongodb://${MONGO_HOST}:27017",
    "database": "ecommerce",
    "topics.regex": "source\\.mongo\\.ecommerce\\..*",
    "writemodel.strategy": "com.mongodb.kafka.connect.sink.writemodel.strategy.ReplaceOneDefaultStrategy",
    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.ProvidedInKeyStrategy",
    "transforms": "unwrap",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.unwrap.drop.tombstones": "true"
  }
}
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add MSK Connect sink connector configurations"
```

---

### Task 23: Test Data Generation Script

**Files:**
- Create: `shared/scripts/generate-test-data.py`

- [ ] **Step 1: Create Python test data generator**

```python
#!/usr/bin/env python3
"""Generate 1GB~10GB of e-commerce test data for PostgreSQL and MongoDB."""
import argparse
import psycopg2
import pymongo
from faker import Faker

# CLI: python generate-test-data.py --size 1 --pg-host x --mongo-host y
# --size in GB (1-10)
# Generates: users, products, orders, order_items, reviews (PG)
#            users, products, orders, reviews, sessions (MongoDB)
# Batch inserts (1000 rows per batch) for performance
```

Full implementation with:
- `argparse` for `--size`, `--pg-host`, `--pg-port`, `--pg-user`, `--pg-password`, `--mongo-host`
- Schema creation (DDL for PostgreSQL, collection creation for MongoDB)
- Faker-based data generation with configurable scale
- Batch inserts for performance (1000 rows per batch)
- Progress bar with `tqdm`

- [ ] **Step 2: Add requirements.txt for test data script**

```
faker>=24.0
psycopg2-binary>=2.9
pymongo>=4.6
tqdm>=4.66
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: add test data generation script (1-10GB e-commerce data)"
```

---

## Part 6: CDK Implementation (Tasks 24-34)

### Task 24: CDK Project Scaffold

**Files:**
- Create: `cdk/bin/app.ts`
- Create: `cdk/lib/config.ts`
- Create: `cdk/package.json`
- Create: `cdk/tsconfig.json`
- Create: `cdk/cdk.json`

- [ ] **Step 1: Initialize CDK project**

```bash
cd /home/ec2-user/my-project/us-h-dr
mkdir -p cdk && cd cdk
npx cdk init app --language typescript
```

- [ ] **Step 2: Create lib/config.ts with centralized configuration**

```typescript
// cdk/lib/config.ts
export const Config = {
  environment: 'dr-lab',
  project: 'us-h-dr',
  primaryRegion: 'us-west-2',
  drRegion: 'us-east-1',
  witnessRegion: 'us-east-2',

  vpcs: {
    onprem: {
      name: 'Onprem',
      cidr: '10.0.0.0/16',
      publicSubnets: ['10.0.0.0/24', '10.0.1.0/24'],
      privateSubnets: ['10.0.16.0/20', '10.0.32.0/20'],
      dataSubnets: ['10.0.48.0/23', '10.0.50.0/23'],
      tgwSubnets: ['10.0.252.0/24', '10.0.253.0/24'],
    },
    uswCenter: {
      name: 'US-W-CENTER',
      cidr: '10.1.0.0/16',
      publicSubnets: ['10.1.0.0/24', '10.1.1.0/24'],
      privateSubnets: ['10.1.16.0/20', '10.1.32.0/20'],
      dataSubnets: ['10.1.48.0/23', '10.1.50.0/23'],
      tgwSubnets: ['10.1.252.0/24', '10.1.253.0/24'],
    },
    useCenter: {
      name: 'US-E-CENTER',
      cidr: '10.2.0.0/16',
      publicSubnets: ['10.2.0.0/24', '10.2.1.0/24'],
      privateSubnets: ['10.2.16.0/20', '10.2.32.0/20'],
      dataSubnets: ['10.2.48.0/23', '10.2.50.0/23'],
      tgwSubnets: ['10.2.252.0/24', '10.2.253.0/24'],
    },
  },

  eks: { version: '1.33', nodeType: 't4g.2xlarge', nodeCount: 8 },
  msk: { instanceType: 'kafka.m7g.xlarge', brokerCount: 4 },
};
```

- [ ] **Step 3: Create bin/app.ts entry point**

```typescript
// cdk/bin/app.ts
import * as cdk from 'aws-cdk-lib';
import { Config } from '../lib/config';
// Stack imports will be added as stacks are created

const app = new cdk.App();

const envWest = { account: process.env.CDK_DEFAULT_ACCOUNT, region: Config.primaryRegion };
const envEast = { account: process.env.CDK_DEFAULT_ACCOUNT, region: Config.drRegion };

// Stacks will be instantiated as they are created in subsequent tasks.

app.synth();
```

- [ ] **Step 4: Validate and commit**

```bash
cd /home/ec2-user/my-project/us-h-dr/cdk
npm install
npx cdk synth --quiet
git add cdk/
git commit -m "feat: scaffold CDK project with centralized config"
```

---

### Task 25: CDK VPC Stacks (OnPrem, US-W, US-E)

**Files:**
- Create: `cdk/lib/onprem-vpc-stack.ts`
- Create: `cdk/lib/usw-center-vpc-stack.ts`
- Create: `cdk/lib/use-center-vpc-stack.ts`

- [ ] **Step 1: Create 3 VPC stack files per spec Section 10.2**

Each stack imports from `config.ts` and creates VPC with 4 subnet tiers, NAT GW, route tables.
Use a shared VPC construct class (internal to the stacks) for DRY code, but each stack is its own file per spec.
Reference: `aws_lab_infra/cdk/lib/vpc01-stack.ts` pattern.

- [ ] **Step 2: Instantiate 3 stacks in app.ts**

- [ ] **Step 3: Validate and commit**

```bash
git commit -m "feat: add CDK VPC stacks for all 3 VPCs"
```

---

### Task 26: CDK VPC Endpoints Stack

**Files:**
- Create: `cdk/lib/vpc-endpoints-stack.ts`

- [ ] **Step 1: Create stack with SSM + DSQL endpoints**

Mirror Terraform vpc-endpoints module.

- [ ] **Step 2: Add to app.ts, validate, commit**

```bash
git commit -m "feat: add CDK VPC endpoints stack (SSM + DSQL PrivateLink)"
```

---

### Task 27: CDK Transit Gateway Stacks

**Files:**
- Create: `cdk/lib/tgw-stack.ts`
- Create: `cdk/lib/tgw-east-stack.ts`
- Create: `cdk/lib/tgw-peering-stack.ts`

- [ ] **Step 1: Create TGW stacks**

Mirror Terraform TGW + peering modules. Use `CfnTransitGateway`, `CfnTransitGatewayAttachment`, `CfnTransitGatewayPeeringAttachment`.

- [ ] **Step 2: Add to app.ts with dependencies, validate, commit**

```bash
git commit -m "feat: add CDK Transit Gateway stacks with inter-region peering"
```

---

### Task 28: CDK CloudFront + ALB Stack

**Files:**
- Create: `cdk/lib/cloudfront-alb-stack.ts`

- [ ] **Step 1: Create stack**

Mirror Terraform cloudfront-alb module. `ApplicationLoadBalancer`, `Distribution`, custom header.

- [ ] **Step 2: Add 3 instances, validate, commit**

```bash
git commit -m "feat: add CDK CloudFront + ALB stack with custom header protection"
```

---

### Task 29: CDK EKS + VSCode Server Stacks

**Files:**
- Create: `cdk/lib/eks-stack.ts`
- Create: `cdk/lib/vscode-server-stack.ts`

- [ ] **Step 1: Create EKS placeholder stack (IAM roles, SGs, eksctl config output)**

- [ ] **Step 2: Create VSCode Server stack**

Reference: `ec2_vscode/infra-cdk/lib/vscode-stack.ts`

- [ ] **Step 3: Add to app.ts, validate, commit**

```bash
git commit -m "feat: add CDK EKS and VSCode Server stacks"
```

---

### Task 30: CDK OnPrem Data Stack

**Files:**
- Create: `cdk/lib/data-onprem-stack.ts`

- [ ] **Step 1: Create stack with PostgreSQL, MongoDB, Kafka, Debezium, MM2 EC2 instances**

Mirror Terraform ec2-database + debezium modules.

- [ ] **Step 2: Add to app.ts, validate, commit**

```bash
git commit -m "feat: add CDK OnPrem data layer stack (PG, Mongo, Kafka, Debezium, MM2)"
```

---

### Task 31: CDK US-W Data Stack (MSK + DSQL + MongoDB)

**Files:**
- Create: `cdk/lib/data-usw-stack.ts`
- Create: `cdk/lib/aurora-dsql-stack.ts`

- [ ] **Step 1: Create US-W data stack (MSK cluster, MongoDB EC2, MSK Connect)**

- [ ] **Step 2: Create Aurora DSQL stack (Multi-Region: Primary + Linked + Witness)**

- [ ] **Step 3: Add to app.ts, validate, commit**

```bash
git commit -m "feat: add CDK US-W data stack and Aurora DSQL multi-region stack"
```

---

### Task 32: CDK US-E Data Stack + MSK Replicator

**Files:**
- Create: `cdk/lib/data-use-stack.ts`
- Create: `cdk/lib/msk-replicator-stack.ts`

- [ ] **Step 1: Create US-E data stack (MSK, MongoDB EC2, MSK Connect)**

- [ ] **Step 2: Create MSK Replicator stack (US-W MSK → US-E MSK)**

- [ ] **Step 3: Add to app.ts, validate, commit**

```bash
git commit -m "feat: add CDK US-E data stack and MSK Replicator stack"
```

---

### Task 33: CDK Monitoring + Route 53 Stacks

**Files:**
- Create: `cdk/lib/monitoring-stack.ts`
- Create: `cdk/lib/route53-failover-stack.ts`

- [ ] **Step 1: Create monitoring stack (CloudWatch alarms, SNS)**

- [ ] **Step 2: Create Route 53 failover stack**

- [ ] **Step 3: Add to app.ts, validate, commit**

```bash
git commit -m "feat: add CDK monitoring and Route 53 failover stacks"
```

---

### Task 34: CDK Final Validation

**Files:**
- Modify: `cdk/bin/app.ts` (ensure all stacks and dependencies are wired)

- [ ] **Step 1: Add all stack dependencies in app.ts**

```typescript
tgwStack.addDependency(onpremVpcStack);
tgwStack.addDependency(uswVpcStack);
// ... etc per deployment sequence
```

- [ ] **Step 2: Full synth validation**

```bash
cd /home/ec2-user/my-project/us-h-dr/cdk
npx cdk synth --quiet
npx cdk list
```

Expected: All stacks listed without errors.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: finalize CDK app.ts with all stack dependencies"
```

---

### Task 35: Terraform test-data Module

**Files:**
- Create: `terraform/modules/test-data/main.tf`
- Create: `terraform/modules/test-data/variables.tf`
- Create: `terraform/modules/test-data/scripts/generate-test-data.py` (symlink or copy from shared/scripts/)

- [ ] **Step 1: Create test-data module with null_resource**

```hcl
# terraform/modules/test-data/main.tf
resource "null_resource" "generate_data" {
  triggers = { data_size = var.data_size_gb }
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = var.vscode_private_ip
      user        = "ec2-user"
    }
    inline = [
      "cd /home/ec2-user",
      "pip3 install faker psycopg2-binary pymongo tqdm",
      "python3 generate-test-data.py --size ${var.data_size_gb} --pg-host ${var.pg_host} --mongo-host ${var.mongo_host}"
    ]
  }
}
```

- [ ] **Step 2: Add to main.tf, validate, commit**

```bash
git commit -m "feat: add Terraform test-data module with null_resource"
```

---

### Task 36: Deploy App Script

**Files:**
- Create: `shared/scripts/deploy-app.sh`

- [ ] **Step 1: Create application deployment script**

Reference: `aws_lab_infra/shared/02.deploy-app.sh`
Deploys sample application to EKS clusters (bilingual or base app).
Includes Kubernetes manifests for Deployment, Service, Ingress.

- [ ] **Step 2: Commit**

```bash
git commit -m "feat: add application deployment script for EKS"
```

---

## Part 7: Validation & Testing (Tasks 37-39)

### Task 35: CloudFront Protection Script

**Files:**
- Create: `shared/scripts/cloudfront-protection.sh`

- [ ] **Step 1: Create script**

Reference: `aws_lab_infra/shared/03.deploy-cloudfront-protection.sh`
Configures ALB SG to use CloudFront prefix list and validates custom header.

- [ ] **Step 2: Commit**

```bash
git commit -m "feat: add CloudFront protection setup script"
```

---

### Task 36: End-to-End Validation Script

**Files:**
- Create: `shared/scripts/validate-replication.sh`

- [ ] **Step 1: Create validation script**

Checks:
1. OnPrem PostgreSQL connectivity
2. OnPrem MongoDB connectivity
3. OnPrem Kafka broker status (4 brokers)
4. Debezium connector status (REST API :8083/connectors)
5. MirrorMaker 2 topic replication lag
6. US-W MSK topic list (verify mirrored topics exist)
7. MSK Connect connector status (AWS CLI)
8. Aurora DSQL connectivity (US-W + US-E)
9. US-W/US-E MongoDB data verification
10. Record count comparison across all DBs

- [ ] **Step 2: Commit**

```bash
git commit -m "feat: add end-to-end replication validation script"
```

---

### Task 37: Operational Runbook

**Files:**
- Create: `shared/docs/runbook.md`

- [ ] **Step 1: Create runbook**

Cover:
- Deployment order (reference spec Section 11)
- Common operations (scale Kafka, restart connectors, check replication lag)
- Troubleshooting (CDC lag, MSK Connect failures, DSQL token refresh)
- DR failover procedure (Route 53, verify US-E DSQL, switch traffic)
- Rollback procedures

- [ ] **Step 2: Commit**

```bash
git commit -m "docs: add operational runbook"
```

---

## Task Summary

| Part | Tasks | Description |
|------|-------|-------------|
| 1 | 1-8 | Terraform Foundation (VPC, TGW, Endpoints, CloudFront, Route53) |
| 2 | 9-11 | Terraform Compute (EKS, VSCode, shared scripts) |
| 3 | 12-18 | Terraform Data Layer (EC2 DBs, MSK Replicator, MSK Connect, DSQL) |
| 4 | 19-20 | Terraform Monitoring + test-data module |
| 5 | 21-24 | Shared Scripts & Test Data |
| 6 | 25-35 | CDK Implementation (all stacks) |
| 7 | 36-39 | Deploy App, CloudFront Protection, Validation, Runbook |

**Total: 39 tasks** with ~160 steps.

**Critical path:** Tasks 1→2→3→5→6 (networking) → 7→8 (ingress) → 14→15 (MSK+DSQL) → 17→18 (MSK Connect+Replicator) → 23 (test data) → 36 (validation)
