# VSCode Server Module

## Role
EC2 instance running code-server (browser IDE) in a private subnet, accessible via ALB.

## Key Inputs
`instance_type`, `vpc_id`, `subnet_id`, `alb_security_group_id`, `password`

## Key Outputs
`instance_id`, `private_ip`, `security_group_id`

## Notes
- AL2023 ARM64, user-data installs: kubectl, eksctl, helm, docker, k9s, AWS CLI v2
- SG allows port 8888 from ALB SG only
- Password is sensitive variable
