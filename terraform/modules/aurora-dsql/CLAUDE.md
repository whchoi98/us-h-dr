# Aurora DSQL Module

## Role
Multi-region Aurora DSQL cluster pair (primary + linked) with witness region for quorum.

## Key Inputs
`cluster_identifier`, `witness_region`, `deletion_protection`

## Key Outputs
`primary_cluster_arn`, `primary_identifier`, `linked_cluster_arn`, `linked_identifier`, `*_vpc_endpoint_service_name`

## Notes
- Uses 3 provider aliases: default (primary), `aws.linked`, `aws.witness`
- Deletion protection enabled by default
- Access via PrivateLink (VPC endpoints created by vpc-endpoints module)
