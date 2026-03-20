# Terraform Module

## Role
Root Terraform configuration managing 282 AWS resources across 3 VPCs in 2 regions (us-west-2, us-east-1) with a witness region (us-east-2).

## Key Files
- `main.tf` - 30 module instantiations + security groups + cross-VPC routes
- `providers.tf` - 3 AWS providers (default, us_east_1, us_east_2)
- `variables.tf` - All project variables with defaults
- `terraform.tfvars` - Environment-specific values
- `backend.tf` - S3 + DynamoDB state backend

## Rules
- All child modules MUST have `required_providers` block
- Use `providers = { aws = aws.us_east_1 }` for cross-region modules
- Run `terraform fmt -recursive && terraform validate` after any change
- Security groups are defined in `main.tf`, not in child modules (cross-module references)
- Tag all resources: Environment, Project, ManagedBy, VPC, Component
