variable "cluster_identifier" {
  description = "Identifier for the Aurora DSQL cluster"
  type        = string
}

variable "witness_region" {
  description = "Witness region for multi-region DSQL cluster"
  type        = string
  default     = "us-east-2"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
