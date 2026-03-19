variable "domain_name" {
  description = "Domain name for the hosted zone"
  type        = string
}

variable "primary_cloudfront_domain" {
  description = "Domain name of the primary CloudFront distribution"
  type        = string
}

variable "secondary_cloudfront_domain" {
  description = "Domain name of the secondary CloudFront distribution"
  type        = string
}

variable "primary_alb_dns" {
  description = "DNS name of the primary ALB for health checks"
  type        = string
}

variable "secondary_alb_dns" {
  description = "DNS name of the secondary ALB for health checks"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
