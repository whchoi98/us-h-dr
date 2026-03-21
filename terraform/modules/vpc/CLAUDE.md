# VPC Module

## Role
Reusable VPC with 4 subnet tiers (public, private, data, TGW) across 2 AZs, with NAT Gateways and route tables.

## Key Inputs
`vpc_name`, `vpc_cidr`, `public_subnets`, `private_subnets`, `data_subnets`, `tgw_subnets`, `availability_zones`

## Key Outputs
`vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `data_subnet_ids`, `tgw_subnet_ids`, `private_route_table_ids`, `data_route_table_ids`

## Notes
- Cross-VPC routes are created in root `main.tf`, not here
- NAT Gateways created per AZ for high availability
