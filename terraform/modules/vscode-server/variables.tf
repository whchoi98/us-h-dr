variable "instance_type" {
  description = "EC2 instance type for the VSCode server"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the VSCode server will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the VSCode server instance"
  type        = string
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB to allow inbound traffic from"
  type        = string
}

variable "password" {
  description = "Password for VSCode server access"
  type        = string
  sensitive   = true
}

variable "vpc_name" {
  description = "Name of the VPC for resource naming"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
