output "primary_cluster_arn" {
  description = "ARN of the primary DSQL cluster"
  value       = aws_dsql_cluster.primary.arn
}

output "primary_identifier" {
  description = "Identifier of the primary DSQL cluster (used as endpoint)"
  value       = aws_dsql_cluster.primary.identifier
}

output "primary_vpc_endpoint_service_name" {
  description = "VPC endpoint service name for the primary DSQL cluster"
  value       = aws_dsql_cluster.primary.vpc_endpoint_service_name
}

output "linked_cluster_arn" {
  description = "ARN of the linked DSQL cluster"
  value       = aws_dsql_cluster.linked.arn
}

output "linked_identifier" {
  description = "Identifier of the linked DSQL cluster (used as endpoint)"
  value       = aws_dsql_cluster.linked.identifier
}

output "linked_vpc_endpoint_service_name" {
  description = "VPC endpoint service name for the linked DSQL cluster"
  value       = aws_dsql_cluster.linked.vpc_endpoint_service_name
}
