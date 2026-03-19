variable "instance_type" {
  description = "EC2 instance type for Debezium Connect worker"
  type        = string
  default     = "m7g.large"
}

variable "subnet_id" {
  description = "Subnet ID to launch the Debezium instance in"
  type        = string
}

variable "kafka_sg_id" {
  description = "Security group ID of the Kafka brokers"
  type        = string
}

variable "vscode_sg_id" {
  description = "Security group ID of the VSCode server"
  type        = string
}

variable "kafka_brokers" {
  description = "Comma-separated list of Kafka broker addresses"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the security group"
  type        = string
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
