output "peering_attachment_id" {
  description = "TGW peering attachment ID"
  value       = aws_ec2_transit_gateway_peering_attachment.this.id
}
