variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS node groups"
  type        = list(string)
}

variable "eks_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "node_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
}

variable "node_count" {
  description = "Number of EKS worker nodes"
  type        = number
}

variable "region" {
  description = "AWS region for the EKS cluster"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones for the EKS cluster"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
