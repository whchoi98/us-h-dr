#!/bin/bash
# =============================================================================
# Generate demo.env from Terraform outputs
# Usage: ./generate-demo-env.sh [terraform-dir]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="${1:-$(dirname "$DEMO_DIR")/../terraform}"
TF_DIR="$(cd "$TF_DIR" && pwd)"
DEMO_ENV="${DEMO_DIR}/demo.env"

echo "=== Generating demo.env from Terraform outputs ==="
echo "Terraform dir: ${TF_DIR}"

cd "$TF_DIR"

# Check terraform state
if ! terraform output onprem_pg_host &>/dev/null; then
  echo "Error: Terraform outputs not available."
  echo "Run 'terraform apply' first, or use 'terraform output' to verify."
  exit 1
fi

# Generate demo.env
cat > "$DEMO_ENV" << EOF
# =============================================================================
# DR Lab Demo Environment — Auto-generated from Terraform outputs
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Re-generate: ./scripts/generate-demo-env.sh
# =============================================================================

# OnPrem VPC (us-west-2)
ONPREM_EKS_CLUSTER="onprem-eks"
ONPREM_PG_HOST="$(terraform output -raw onprem_pg_host)"
ONPREM_MONGO_HOST="$(terraform output -raw onprem_mongo_host)"
ONPREM_KAFKA_BROKERS="$(terraform output -raw onprem_kafka_brokers)"
ONPREM_DEBEZIUM_HOST="$(terraform output -raw onprem_debezium_host)"
ONPREM_CF_DOMAIN="$(terraform output -raw onprem_cf_domain)"

# US-W VPC (us-west-2)
USW_MONGO_HOST="$(terraform output -raw usw_mongo_host)"
USW_MSK_BROKERS="$(terraform output -raw usw_msk_brokers_iam)"
USW_DSQL_ENDPOINT="$(terraform output -raw usw_dsql_endpoint)"

# US-E VPC (us-east-1) — DR
USE_MONGO_HOST="$(terraform output -raw use_mongo_host)"
USE_MSK_BROKERS="$(terraform output -raw use_msk_brokers_iam)"
USE_DSQL_ENDPOINT="$(terraform output -raw use_dsql_endpoint)"

# Demo Settings
PG_USER="debezium"
PG_DB="ecommerce"
MONGO_DB="ecommerce"
DEMO_RECORD_COUNT=100
EOF

echo ""
echo "Generated: ${DEMO_ENV}"
echo ""
cat "$DEMO_ENV"
echo ""
echo "=== Done. Run: cd $(dirname "$DEMO_ENV") && ./run-demo.sh all ==="
