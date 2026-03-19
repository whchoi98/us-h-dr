output "instance_id" {
  description = "ID of the VSCode server EC2 instance"
  value       = aws_instance.vscode.id
}

output "private_ip" {
  description = "Private IP address of the VSCode server"
  value       = aws_instance.vscode.private_ip
}

output "security_group_id" {
  description = "Security group ID of the VSCode server"
  value       = aws_security_group.vscode.id
}
