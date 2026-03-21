# EKS Module

## Role
IAM roles, security groups, and eksctl config template for EKS clusters. Cluster creation is done via eksctl (not Terraform).

## Key Inputs
`cluster_name`, `vpc_id`, `private_subnet_ids`, `eks_version`, `node_type`, `node_count`

## Key Outputs
`cluster_role_arn`, `node_role_arn`, `eks_node_security_group_id`, `eksctl_config_path`

## Notes
- Generates `shared/configs/eksctl-<cluster_name>.yaml` via templatefile
- Includes KMS key for Secrets encryption and CloudWatch logging config
- Actual cluster creation: `eksctl create cluster -f <config.yaml>`
