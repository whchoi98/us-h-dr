# Route 53 Failover Module

## Role
Active-passive DNS failover between primary (US-W) and secondary (US-E) CloudFront distributions.

## Key Inputs
`domain_name`, `primary_cloudfront_domain`, `secondary_cloudfront_domain`

## Key Outputs
`hosted_zone_id`, `primary_health_check_id`, `secondary_health_check_id`

## Notes
- Creates hosted zone, health checks, and failover alias records
- Uses CloudFront global zone ID (Z2FDTNDATAQYW2)
