# MSK Replicator Module

## Role
Cross-region MSK topic replication from source (US-W) to target (US-E) cluster.

## Key Inputs
`source_msk_arn`, `target_msk_arn`, `source_subnet_ids`, `target_subnet_ids`, `service_execution_role_arn`

## Key Outputs
`replicator_arn`

## Notes
- IAM role and cluster policies created in root `main.tf` (not here) to break circular deps
- Deployed in target region (us-east-1)
- Replicates all topics except internal (`__.*`)
