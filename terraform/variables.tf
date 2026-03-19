# -----------------------------------------------------------------------------
# Region Configuration
# -----------------------------------------------------------------------------
variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-west-2"
}

variable "dr_region" {
  description = "Disaster recovery AWS region"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Project Metadata
# -----------------------------------------------------------------------------
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dr-lab"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "us-h-dr"
}

# -----------------------------------------------------------------------------
# VPC CIDRs
# -----------------------------------------------------------------------------
variable "onprem_vpc_cidr" {
  description = "CIDR block for the simulated on-premises VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "usw_center_vpc_cidr" {
  description = "CIDR block for the US-West center VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "use_center_vpc_cidr" {
  description = "CIDR block for the US-East center VPC"
  type        = string
  default     = "10.2.0.0/16"
}

# -----------------------------------------------------------------------------
# On-Prem VPC Subnets (10.0.0.0/16)
# -----------------------------------------------------------------------------
variable "onprem_public_subnets" {
  description = "Public subnet CIDRs for the on-prem VPC"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "onprem_private_subnets" {
  description = "Private subnet CIDRs for the on-prem VPC"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "onprem_data_subnets" {
  description = "Data subnet CIDRs for the on-prem VPC"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "onprem_tgw_subnets" {
  description = "Transit Gateway subnet CIDRs for the on-prem VPC"
  type        = list(string)
  default     = ["10.0.252.0/24", "10.0.253.0/24"]
}

# -----------------------------------------------------------------------------
# US-West Center VPC Subnets (10.1.0.0/16)
# -----------------------------------------------------------------------------
variable "usw_center_public_subnets" {
  description = "Public subnet CIDRs for the US-West center VPC"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "usw_center_private_subnets" {
  description = "Private subnet CIDRs for the US-West center VPC"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24"]
}

variable "usw_center_data_subnets" {
  description = "Data subnet CIDRs for the US-West center VPC"
  type        = list(string)
  default     = ["10.1.20.0/24", "10.1.21.0/24"]
}

variable "usw_center_tgw_subnets" {
  description = "Transit Gateway subnet CIDRs for the US-West center VPC"
  type        = list(string)
  default     = ["10.1.252.0/24", "10.1.253.0/24"]
}

# -----------------------------------------------------------------------------
# US-East Center VPC Subnets (10.2.0.0/16)
# -----------------------------------------------------------------------------
variable "use_center_public_subnets" {
  description = "Public subnet CIDRs for the US-East center VPC"
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24"]
}

variable "use_center_private_subnets" {
  description = "Private subnet CIDRs for the US-East center VPC"
  type        = list(string)
  default     = ["10.2.10.0/24", "10.2.11.0/24"]
}

variable "use_center_data_subnets" {
  description = "Data subnet CIDRs for the US-East center VPC"
  type        = list(string)
  default     = ["10.2.20.0/24", "10.2.21.0/24"]
}

variable "use_center_tgw_subnets" {
  description = "Transit Gateway subnet CIDRs for the US-East center VPC"
  type        = list(string)
  default     = ["10.2.252.0/24", "10.2.253.0/24"]
}

# -----------------------------------------------------------------------------
# EKS Configuration
# -----------------------------------------------------------------------------
variable "eks_version" {
  description = "Kubernetes version for EKS clusters"
  type        = string
  default     = "1.33"
}

variable "eks_node_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t4g.2xlarge"
}

variable "eks_node_count" {
  description = "Number of EKS worker nodes per cluster"
  type        = number
  default     = 8
}

# -----------------------------------------------------------------------------
# Data Layer Configuration
# -----------------------------------------------------------------------------
variable "db_instance_type" {
  description = "RDS instance type for Aurora PostgreSQL"
  type        = string
  default     = "r7g.large"
}

variable "kafka_instance_type" {
  description = "EC2 instance type for Kafka brokers"
  type        = string
  default     = "m7g.xlarge"
}

variable "kafka_broker_count" {
  description = "Number of Kafka broker nodes"
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# MSK Configuration
# -----------------------------------------------------------------------------
variable "msk_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.m7g.xlarge"
}

variable "msk_broker_count" {
  description = "Number of MSK broker nodes"
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# VSCode Server Configuration
# -----------------------------------------------------------------------------
variable "vscode_instance_type" {
  description = "EC2 instance type for VSCode server"
  type        = string
  default     = "m7g.xlarge"
}

variable "vscode_password" {
  description = "Password for VSCode server access"
  type        = string
  sensitive   = true
  default     = ""
}
