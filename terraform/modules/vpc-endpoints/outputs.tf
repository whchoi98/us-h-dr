output "endpoint_ids" {
  description = "Map of service name to VPC endpoint ID"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "vpce_security_group_id" {
  description = "Security group ID for VPC endpoints"
  value       = aws_security_group.vpce.id
}
