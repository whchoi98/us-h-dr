# -----------------------------------------------------------------------------
# Route 53 Hosted Zone
# -----------------------------------------------------------------------------

resource "aws_route53_zone" "this" {
  name = var.domain_name

  tags = merge(var.tags, { Name = var.domain_name })
}

# -----------------------------------------------------------------------------
# Health Checks
# -----------------------------------------------------------------------------

resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, { Name = "primary-alb-health-check" })
}

resource "aws_route53_health_check" "secondary" {
  fqdn              = var.secondary_alb_dns
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = merge(var.tags, { Name = "secondary-alb-health-check" })
}

# -----------------------------------------------------------------------------
# Failover Records (alias to CloudFront distributions)
# -----------------------------------------------------------------------------

resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = var.primary_cloudfront_domain
    zone_id                = "Z2FDTNDATAQYW2" # CloudFront hosted zone ID (global constant)
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary.id

  alias {
    name                   = var.secondary_cloudfront_domain
    zone_id                = "Z2FDTNDATAQYW2" # CloudFront hosted zone ID (global constant)
    evaluate_target_health = true
  }
}
