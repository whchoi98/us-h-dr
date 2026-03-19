variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_name" {
  description = "Name of the VPC (for resource naming)"
  type        = string
}

variable "region" {
  description = "AWS region for endpoint service names"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for interface endpoints"
  type        = list(string)
}

variable "enable_dsql_endpoint" {
  description = "Whether to create a DSQL VPC endpoint"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
