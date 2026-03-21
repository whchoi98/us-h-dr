variable "connector_name" {
  description = "Name of the MSK Connect connector"
  type        = string
}

variable "connector_class" {
  description = "Java class for the Kafka connector"
  type        = string
}

variable "msk_cluster_arn" {
  description = "ARN of the MSK cluster"
  type        = string
}

variable "msk_bootstrap_servers" {
  description = "Bootstrap servers for the MSK cluster"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the MSK Connect connector"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for the MSK Connect connector"
  type        = list(string)
}

variable "plugin_s3_bucket" {
  description = "S3 bucket name where connector plugin JARs are stored"
  type        = string
}

variable "plugin_s3_key" {
  description = "S3 object key for the connector plugin ZIP/JAR"
  type        = string
}

variable "connector_configuration" {
  description = "Map of connector configuration key-value pairs"
  type        = map(string)
}

variable "worker_count" {
  description = "Number of workers allocated to the connector"
  type        = number
  default     = 1
}

variable "dsql_cluster_arn" {
  description = "ARN of the Aurora DSQL cluster (optional, for JDBC connectors)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
