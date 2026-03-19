output "tgw_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.this.id
}

output "tgw_route_table_id" {
  description = "Transit Gateway route table ID"
  value       = aws_ec2_transit_gateway_route_table.this.id
}

output "tgw_attachment_ids" {
  description = "Map of VPC attachment IDs"
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}
