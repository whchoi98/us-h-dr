variable "cluster_name" {
  description = "Name of the MSK cluster"
  type        = string
}

variable "kafka_version" {
  description = "Apache Kafka version for the MSK cluster"
  type        = string
  default     = "3.7.x.kraft"
}

variable "broker_instance_type" {
  description = "Instance type for MSK broker nodes"
  type        = string
}

variable "number_of_broker_nodes" {
  description = "Number of broker nodes in the MSK cluster"
  type        = number
}

variable "subnet_ids" {
  description = "List of subnet IDs for MSK broker placement"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for the MSK security group"
  type        = string
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access MSK"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
