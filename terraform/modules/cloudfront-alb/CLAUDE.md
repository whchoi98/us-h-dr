# CloudFront + ALB Module

## Role
CloudFront distribution fronting an ALB with custom header protection. ALB restricted to CloudFront prefix list only.

## Key Inputs
`vpc_id`, `public_subnet_ids`, `custom_header_value`, `certificate_arn`

## Key Outputs
`alb_arn`, `alb_dns_name`, `alb_security_group_id`, `cloudfront_domain_name`

## Security
- ALB SG allows HTTP only from CloudFront managed prefix list
- X-Custom-Secret header validated at ALB listener rules
