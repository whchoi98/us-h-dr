variable "name" {
  description = "Name for the Transit Gateway"
  type        = string
}

variable "amazon_side_asn" {
  description = "Amazon side ASN for the Transit Gateway"
  type        = number
}

variable "vpc_attachments" {
  description = "Map of VPC attachments"
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
    vpc_cidr   = string
  }))
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
