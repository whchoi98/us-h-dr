# TGW Peering Module

## Role
Inter-region Transit Gateway peering between us-west-2 and us-east-1 with bidirectional static routes.

## Key Inputs
`requester_tgw_id`, `accepter_tgw_id`, `requester_cidrs_to_route`, `accepter_cidrs_to_route`

## Key Outputs
`peering_attachment_id`

## Notes
- Uses two providers: default (requester) and `aws.accepter` (accepter region)
- Static routes added to both TGW route tables
