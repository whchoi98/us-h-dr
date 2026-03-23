---
name: terraform-guide
description: Terraform module conventions and rules for the us-h-dr project. Use when working with Terraform files.
---

# Terraform Guide

## Structure
- `main.tf` — 30 module instantiations + security groups + cross-VPC routes
- `providers.tf` — 3 AWS providers (default us-west-2, us_east_1, us_east_2)
- `variables.tf` — All project variables with defaults
- `backend.tf` — S3 + DynamoDB state backend
- `modules/` — 16 reusable modules (vpc, tgw, msk, eks, aurora-dsql, etc.)

## Rules
- All child modules MUST have `required_providers` block
- Use `providers = { aws = aws.us_east_1 }` for cross-region modules
- Run `terraform fmt -recursive && terraform validate` after any change
- Security groups defined in `main.tf`, not in child modules (cross-module references)
- Tag all resources: Environment, Project, ManagedBy, VPC, Component
