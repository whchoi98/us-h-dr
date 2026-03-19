variable "replicator_name" {
  description = "Name of the MSK replicator"
  type        = string
}

variable "source_msk_arn" {
  description = "ARN of the source MSK cluster"
  type        = string
}

variable "target_msk_arn" {
  description = "ARN of the target MSK cluster"
  type        = string
}

variable "source_subnet_ids" {
  description = "Subnet IDs for the source MSK cluster VPC connectivity"
  type        = list(string)
}

variable "target_subnet_ids" {
  description = "Subnet IDs for the target MSK cluster VPC connectivity"
  type        = list(string)
}

variable "source_security_group_ids" {
  description = "Security group IDs for source cluster replicator ENIs"
  type        = list(string)
  default     = []
}

variable "target_security_group_ids" {
  description = "Security group IDs for target cluster replicator ENIs"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
