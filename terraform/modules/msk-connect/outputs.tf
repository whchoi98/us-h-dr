output "connector_arn" {
  description = "ARN of the MSK Connect connector"
  value       = aws_mskconnect_connector.this.arn
}

output "connector_name" {
  description = "Name of the MSK Connect connector"
  value       = aws_mskconnect_connector.this.name
}

output "custom_plugin_arn" {
  description = "ARN of the custom plugin"
  value       = aws_mskconnect_custom_plugin.this.arn
}
