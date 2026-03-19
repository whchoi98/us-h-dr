output "instance_ids" {
  description = "Map of instance keys to instance IDs"
  value       = { for k, v in aws_instance.db : k => v.id }
}

output "private_ips" {
  description = "Map of instance keys to private IP addresses"
  value       = { for k, v in aws_instance.db : k => v.private_ip }
}
