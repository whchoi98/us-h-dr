output "replicator_arn" {
  description = "ARN of the MSK Replicator"
  value       = aws_msk_replicator.this.arn
}
