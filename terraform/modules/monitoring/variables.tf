variable "region" {
  description = "AWS region identifier for naming"
  type        = string
}

variable "msk_cluster_name" {
  description = "Name of the MSK cluster to monitor"
  type        = string
}

variable "sns_email" {
  description = "Email address for SNS alarm notifications (leave empty to skip)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
