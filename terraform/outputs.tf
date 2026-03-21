# =============================================================================
# Root Outputs — Used by demo scripts and operational tooling
# =============================================================================

# -----------------------------------------------------------------------------
# OnPrem VPC (us-west-2)
# -----------------------------------------------------------------------------

output "onprem_eks_cluster" {
  description = "OnPrem EKS cluster name"
  value       = module.onprem_eks.eksctl_config_path
}

output "onprem_pg_host" {
  description = "OnPrem PostgreSQL private IP"
  value       = module.onprem_databases.private_ips["postgresql"]
}

output "onprem_mongo_host" {
  description = "OnPrem MongoDB private IP"
  value       = module.onprem_databases.private_ips["mongodb"]
}

output "onprem_kafka_brokers" {
  description = "OnPrem Kafka broker addresses (port 9092)"
  value = join(",", [
    for k, ip in module.onprem_databases.private_ips :
    "${ip}:9092" if startswith(k, "kafka")
  ])
}

output "onprem_debezium_host" {
  description = "OnPrem Debezium Kafka Connect private IP"
  value       = module.onprem_debezium.private_ip
}

output "onprem_cf_domain" {
  description = "OnPrem CloudFront distribution domain"
  value       = module.onprem_ingress.cloudfront_domain_name
}

output "onprem_alb_dns" {
  description = "OnPrem ALB DNS name"
  value       = module.onprem_ingress.alb_dns_name
}

output "onprem_vscode_ip" {
  description = "OnPrem VSCode Server private IP"
  value       = module.onprem_vscode.private_ip
}

# -----------------------------------------------------------------------------
# US-W-CENTER VPC (us-west-2)
# -----------------------------------------------------------------------------

output "usw_mongo_host" {
  description = "US-W MongoDB private IP"
  value       = module.usw_mongodb.private_ips["mongodb"]
}

output "usw_msk_brokers_iam" {
  description = "US-W MSK bootstrap brokers (IAM auth, port 9098)"
  value       = module.msk_usw.bootstrap_brokers_iam
}

output "usw_msk_brokers_tls" {
  description = "US-W MSK bootstrap brokers (TLS, port 9094)"
  value       = module.msk_usw.bootstrap_brokers_tls
}

output "usw_dsql_endpoint" {
  description = "Aurora DSQL primary cluster identifier (US-W)"
  value       = module.aurora_dsql.primary_identifier
}

output "usw_dsql_arn" {
  description = "Aurora DSQL primary cluster ARN"
  value       = module.aurora_dsql.primary_cluster_arn
}

output "usw_cf_domain" {
  description = "US-W CloudFront distribution domain"
  value       = module.usw_ingress.cloudfront_domain_name
}

# -----------------------------------------------------------------------------
# US-E-CENTER VPC (us-east-1) — DR
# -----------------------------------------------------------------------------

output "use_mongo_host" {
  description = "US-E MongoDB private IP"
  value       = module.use_mongodb.private_ips["mongodb"]
}

output "use_msk_brokers_iam" {
  description = "US-E MSK bootstrap brokers (IAM auth, port 9098)"
  value       = module.msk_use.bootstrap_brokers_iam
}

output "use_msk_brokers_tls" {
  description = "US-E MSK bootstrap brokers (TLS, port 9094)"
  value       = module.msk_use.bootstrap_brokers_tls
}

output "use_dsql_endpoint" {
  description = "Aurora DSQL linked cluster identifier (US-E)"
  value       = module.aurora_dsql.linked_identifier
}

output "use_dsql_arn" {
  description = "Aurora DSQL linked cluster ARN"
  value       = module.aurora_dsql.linked_cluster_arn
}

output "use_cf_domain" {
  description = "US-E CloudFront distribution domain"
  value       = module.use_ingress.cloudfront_domain_name
}

# -----------------------------------------------------------------------------
# Demo Environment — auto-generates demo.env
# -----------------------------------------------------------------------------

output "demo_env" {
  description = "Complete demo.env content (paste into shared/demo/demo.env)"
  value       = <<-EOT
    # Auto-generated from: terraform output -raw demo_env
    # Generated at: ${timestamp()}

    # OnPrem VPC (us-west-2)
    ONPREM_EKS_CLUSTER="onprem-eks"
    ONPREM_PG_HOST="${module.onprem_databases.private_ips["postgresql"]}"
    ONPREM_MONGO_HOST="${module.onprem_databases.private_ips["mongodb"]}"
    ONPREM_KAFKA_BROKERS="${join(",", [for k, ip in module.onprem_databases.private_ips : "${ip}:9092" if startswith(k, "kafka")])}"
    ONPREM_DEBEZIUM_HOST="${module.onprem_debezium.private_ip}"
    ONPREM_CF_DOMAIN="${module.onprem_ingress.cloudfront_domain_name}"

    # US-W VPC (us-west-2)
    USW_MONGO_HOST="${module.usw_mongodb.private_ips["mongodb"]}"
    USW_MSK_BROKERS="${module.msk_usw.bootstrap_brokers_iam}"
    USW_DSQL_ENDPOINT="${module.aurora_dsql.primary_identifier}"

    # US-E VPC (us-east-1) — DR
    USE_MONGO_HOST="${module.use_mongodb.private_ips["mongodb"]}"
    USE_MSK_BROKERS="${module.msk_use.bootstrap_brokers_iam}"
    USE_DSQL_ENDPOINT="${module.aurora_dsql.linked_identifier}"

    # Demo Settings
    PG_USER="debezium"
    PG_DB="ecommerce"
    MONGO_DB="ecommerce"
    DEMO_RECORD_COUNT=100
  EOT
}
