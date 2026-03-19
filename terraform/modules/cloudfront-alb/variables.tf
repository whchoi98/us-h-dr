variable "vpc_id" {
  description = "VPC ID to deploy ALB into"
  type        = string
}

variable "vpc_name" {
  description = "Name prefix for resources"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB placement"
  type        = list(string)
}

variable "custom_header_value" {
  description = "Secret value for X-Custom-Secret header between CloudFront and ALB"
  type        = string
  sensitive   = true
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS (optional for lab)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
