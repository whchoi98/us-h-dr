# Transit Gateway Module

## Role
Creates a Transit Gateway with VPC attachments and a single route table. Supports multi-VPC hub-spoke topology.

## Key Inputs
`name`, `amazon_side_asn`, `vpc_attachments` (map of vpc_id/subnet_ids/vpc_cidr)

## Key Outputs
`tgw_id`, `tgw_route_table_id`, `tgw_attachment_ids`
