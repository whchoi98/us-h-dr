output "hosted_zone_id" {
  description = "ID of the Route 53 hosted zone"
  value       = aws_route53_zone.this.zone_id
}

output "primary_health_check_id" {
  description = "ID of the primary ALB health check"
  value       = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  description = "ID of the secondary ALB health check"
  value       = aws_route53_health_check.secondary.id
}
