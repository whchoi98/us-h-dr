# VPC Endpoints Module

## Role
SSM VPC endpoints (all VPCs) and optional DSQL PrivateLink endpoint (US-W/US-E only).

## Key Inputs
`vpc_id`, `subnet_ids`, `enable_dsql_endpoint`, `region`

## Key Outputs
`endpoint_ids`, `vpce_security_group_id`
