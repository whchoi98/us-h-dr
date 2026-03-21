# MSK Connect Module

## Role
MSK Connect connector with custom plugin from S3, IAM role with least-privilege, and CloudWatch logging.

## Key Inputs
`connector_name`, `connector_class`, `msk_cluster_arn`, `msk_bootstrap_servers`, `plugin_s3_bucket`, `dsql_cluster_arn` (optional)

## Key Outputs
`connector_arn`, `custom_plugin_arn`

## Security
- IAM policy scoped to specific MSK cluster/topic/group ARNs and S3 bucket
- DSQL access only granted when `dsql_cluster_arn` is provided
- CloudWatch logs scoped to connector-specific log group
