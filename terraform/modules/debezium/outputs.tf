output "instance_id" {
  description = "ID of the Debezium EC2 instance"
  value       = aws_instance.debezium.id
}

output "private_ip" {
  description = "Private IP address of the Debezium instance"
  value       = aws_instance.debezium.private_ip
}

output "sg_id" {
  description = "Security group ID of the Debezium instance"
  value       = aws_security_group.debezium.id
}
