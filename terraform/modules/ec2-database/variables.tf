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

variable "kafka_quorum_voters" {
  description = "KRaft quorum voters string (e.g., 0@ip1:9093,1@ip2:9093)"
  type        = string
  default     = ""
}

variable "kafka_cluster_id" {
  description = "KRaft cluster ID (shared across all brokers)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
