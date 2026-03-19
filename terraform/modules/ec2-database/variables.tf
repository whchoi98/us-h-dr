variable "instances" {
  description = "Map of EC2 database instances to create"
  type = map(object({
    instance_type  = string
    subnet_id      = string
    user_data_file = string
    sg_ids         = list(string)
    name           = string
  }))
}

variable "vpc_name" {
  description = "Name of the VPC for resource naming"
  type        = string
}

variable "iam_policies" {
  description = "List of IAM policy ARNs to attach to the instance role"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
