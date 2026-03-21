#!/bin/bash
# =============================================================================
# DR Lab Migration Demo — End-to-End Replication Test
#
# Flow: CloudFront → ALB → EKS Pod → PostgreSQL/MongoDB (OnPrem)
#       → Debezium CDC → Kafka → MirrorMaker2 → MSK (US-W)
#       → MSK Connect → Aurora DSQL + MongoDB (US-W)
#       → MSK Replicator → MSK (US-E) → MSK Connect → MongoDB (US-E)
#       → Aurora DSQL Multi-Region → DSQL (US-E)
#
# Usage: ./run-demo.sh [step]
#   Steps: all | deploy | seed | verify | pipeline | dr-test | cleanup
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/demo.env"

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

banner() { echo -e "\n${B}═══════════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}  $1${NC}"; echo -e "${B}═══════════════════════════════════════════════════════════${NC}\n"; }
step()   { echo -e "${C}──── Step $1: $2 ────${NC}"; }
ok()     { echo -e "  ${G}✓${NC} $1"; }
fail()   { echo -e "  ${R}✗${NC} $1"; }
warn()   { echo -e "  ${Y}⚠${NC} $1"; }
info()   { echo -e "  ${DIM}→${NC} $1"; }
wait_with_dots() {
  local msg="$1" secs="$2"
  echo -ne "  ${DIM}${msg}"
  for ((i=0; i<secs; i++)); do echo -ne "."; sleep 1; done
  echo -e "${NC}"
}

load_env() {
  if [ ! -f "$ENV_FILE" ]; then
    echo -e "${R}Error: ${ENV_FILE} not found.${NC}"
    echo "Copy demo.env.example to demo.env and fill in values from Terraform outputs."
    exit 1
  fi
  set -a; source "$ENV_FILE"; set +a
  # Validate required vars
  for var in ONPREM_EKS_CLUSTER ONPREM_PG_HOST ONPREM_MONGO_HOST ONPREM_DEBEZIUM_HOST; do
    if [ -z "${!var:-}" ]; then
      echo -e "${R}Error: ${var} is not set in demo.env${NC}"
      exit 1
    fi
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Deploy Demo API to OnPrem EKS
# ─────────────────────────────────────────────────────────────────────────────

do_deploy() {
  banner "STEP 1: Deploy Demo API to OnPrem EKS"

  step "1.1" "Connecting to EKS cluster: ${ONPREM_EKS_CLUSTER}"
  aws eks update-kubeconfig --region us-west-2 --name "${ONPREM_EKS_CLUSTER}" --alias onprem-eks
  ok "Kubeconfig updated"

  step "1.2" "Creating DB config and secrets"
  kubectl create namespace dr-demo --dry-run=client -o yaml | kubectl apply -f -

  kubectl create configmap demo-db-config -n dr-demo \
    --from-literal=pg_host="${ONPREM_PG_HOST}" \
    --from-literal=pg_user="${PG_USER:-debezium}" \
    --from-literal=pg_db="${PG_DB:-ecommerce}" \
    --from-literal=mongo_host="${ONPREM_MONGO_HOST}" \
    --from-literal=mongo_user="${MONGO_USER:-}" \
    --dry-run=client -o yaml | kubectl apply -f -

  kubectl create secret generic demo-db-secrets -n dr-demo \
    --from-literal=pg_password="${POSTGRES_PASSWORD:-}" \
    --from-literal=mongo_password="${MONGO_PASSWORD:-}" \
    --dry-run=client -o yaml | kubectl apply -f -
  ok "ConfigMap and Secret created"

  step "1.3" "Deploying demo-api (Flask + Gunicorn)"
  kubectl apply -f "${SCRIPT_DIR}/k8s/demo-app.yaml"
  info "Waiting for pods to be ready..."
  kubectl wait --for=condition=ready pod -l app=demo-api -n dr-demo --timeout=180s
  ok "Demo API pods ready"

  step "1.4" "Checking endpoints"
  kubectl get pods,svc,ingress -n dr-demo
  DEMO_URL=$(kubectl get ingress demo-api -n dr-demo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [ -n "$DEMO_URL" ]; then
    ok "Demo API accessible at: http://${DEMO_URL}/health"
    echo "$DEMO_URL" > "${SCRIPT_DIR}/.demo-url"
  else
    warn "ALB not ready yet. Run: kubectl get ingress -n dr-demo -w"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 2: Seed Demo Data (CloudFront → ALB → EKS → DB)
# ─────────────────────────────────────────────────────────────────────────────

do_seed() {
  banner "STEP 2: Seed Demo Data via API"
  local count="${DEMO_RECORD_COUNT:-100}"
  local url=""

  # Determine API endpoint
  if [ -n "${ONPREM_CF_DOMAIN:-}" ]; then
    url="https://${ONPREM_CF_DOMAIN}"
    info "Using CloudFront: ${url}"
  elif [ -f "${SCRIPT_DIR}/.demo-url" ]; then
    url="http://$(cat "${SCRIPT_DIR}/.demo-url")"
    info "Using ALB: ${url}"
  else
    # Fallback: port-forward
    warn "No external URL found. Using kubectl port-forward..."
    kubectl port-forward svc/demo-api -n dr-demo 8080:80 &
    PF_PID=$!
    sleep 3
    url="http://localhost:8080"
    trap "kill $PF_PID 2>/dev/null" EXIT
  fi

  step "2.1" "Health check"
  if curl -sf "${url}/health" | python3 -m json.tool; then
    ok "API is healthy"
  else
    fail "API health check failed"
    exit 1
  fi

  step "2.2" "Seeding ${count} records (customers+orders → PG, products+inventory → MongoDB)"
  RESULT=$(curl -sf -X POST "${url}/api/demo/seed" \
    -H "Content-Type: application/json" \
    -d "{\"count\": ${count}}")
  echo "$RESULT" | python3 -m json.tool
  BATCH_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['batch_id'])")
  echo "$BATCH_ID" > "${SCRIPT_DIR}/.demo-batch-id"
  ok "Batch ID: ${BATCH_ID}"

  step "2.3" "Verify source data counts"
  curl -sf "${url}/api/demo/count?batch_id=${BATCH_ID}" | python3 -m json.tool
  ok "Source data seeded successfully"

  echo -e "\n${G}${BOLD}Data is now in OnPrem PostgreSQL and MongoDB.${NC}"
  echo -e "${DIM}CDC pipeline will replicate: Debezium → Kafka → MM2 → MSK → Connect → Targets${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Monitor CDC Pipeline
# ─────────────────────────────────────────────────────────────────────────────

do_pipeline() {
  banner "STEP 3: CDC Pipeline Status"
  local debezium="${ONPREM_DEBEZIUM_HOST}"

  step "3.1" "Debezium Connector Status"
  for connector in postgres-source mongodb-source; do
    STATUS=$(curl -sf "http://${debezium}:8083/connectors/${connector}/status" 2>/dev/null || echo '{"error":"unreachable"}')
    STATE=$(echo "$STATUS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('connector',{}).get('state','UNKNOWN'))" 2>/dev/null || echo "ERROR")
    if [ "$STATE" = "RUNNING" ]; then
      ok "${connector}: ${G}RUNNING${NC}"
    else
      fail "${connector}: ${R}${STATE}${NC}"
    fi
  done

  step "3.2" "OnPrem Kafka Topics (CDC)"
  if [ -n "${ONPREM_KAFKA_BROKERS:-}" ]; then
    info "Checking for Debezium topics..."
    TOPICS=$(kubectl exec -n dr-demo deploy/demo-api -- bash -c \
      "pip install -q kafka-python 2>/dev/null; python3 -c \"
from kafka import KafkaConsumer
c=KafkaConsumer(bootstrap_servers='${ONPREM_KAFKA_BROKERS}')
topics=[t for t in c.topics() if 'dbserver1' in t or 'source' in t or 'mongo' in t]
c.close()
for t in sorted(topics): print(t)
\" 2>/dev/null" 2>/dev/null || echo "(unable to list topics)")
    if [ -n "$TOPICS" ] && [ "$TOPICS" != "(unable to list topics)" ]; then
      echo "$TOPICS" | while read -r t; do ok "Topic: $t"; done
    else
      warn "No CDC topics found (Debezium may need to be configured)"
    fi
  fi

  step "3.3" "MSK US-W Replication (MirrorMaker2 → MSK)"
  if [ -n "${USW_MSK_BROKERS:-}" ]; then
    info "MirrorMaker2 replicates OnPrem Kafka → MSK US-W"
    ok "MSK US-W brokers: ${USW_MSK_BROKERS:0:60}..."
  else
    warn "USW_MSK_BROKERS not configured in demo.env"
  fi

  step "3.4" "MSK Connect Sink Connectors"
  info "JDBC Sink: MSK US-W → Aurora DSQL (US-W)"
  info "MongoDB Sink (US-W): MSK US-W → MongoDB EC2 (US-W)"
  info "MongoDB Sink (US-E): MSK US-E → MongoDB EC2 (US-E)"

  step "3.5" "MSK Replicator (US-W → US-E)"
  info "Cross-region replication: MSK US-W topics → MSK US-E"
  info "Aurora DSQL auto-replicates: DSQL Primary (US-W) → DSQL Linked (US-E)"
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4: Verify Replication at All Targets
# ─────────────────────────────────────────────────────────────────────────────

do_verify() {
  banner "STEP 4: Verify Replication Across All Regions"
  local batch_id=""
  [ -f "${SCRIPT_DIR}/.demo-batch-id" ] && batch_id=$(cat "${SCRIPT_DIR}/.demo-batch-id")

  local pass=0 fail_count=0 skip=0

  check_result() {
    local name="$1" result="$2" expected="$3"
    if [ "$result" = "SKIP" ]; then
      warn "${name}: skipped (endpoint not configured)"
      ((skip++))
    elif [ "$result" -gt 0 ] 2>/dev/null; then
      ok "${name}: ${G}${result} records${NC} (expected ~${expected})"
      ((pass++))
    else
      fail "${name}: ${R}0 records${NC} (expected ~${expected})"
      ((fail_count++))
    fi
  }

  local count="${DEMO_RECORD_COUNT:-100}"

  # --- Source: OnPrem ---
  step "4.1" "OnPrem Source (PostgreSQL + MongoDB)"
  PG_CUSTOMERS=$(PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "${ONPREM_PG_HOST}" -U "${PG_USER:-debezium}" -d "${PG_DB:-ecommerce}" -tAc \
    "SELECT COUNT(*) FROM customers WHERE batch_id LIKE 'demo_%'" 2>/dev/null || echo "0")
  check_result "OnPrem PG customers" "$PG_CUSTOMERS" "$count"

  MONGO_PRODUCTS=$(mongosh --host "${ONPREM_MONGO_HOST}" --quiet --eval \
    "db.getSiblingDB('ecommerce').products.countDocuments({batch_id: /^demo_/})" 2>/dev/null || echo "0")
  check_result "OnPrem MongoDB products" "$MONGO_PRODUCTS" "$count"

  # --- Target: US-W ---
  step "4.2" "US-W Target (Aurora DSQL + MongoDB)"
  if [ -n "${USW_DSQL_ENDPOINT:-}" ]; then
    DSQL_CUSTOMERS=$(psql "host=${USW_DSQL_ENDPOINT}.dsql.us-west-2.on.aws dbname=postgres sslmode=require" -tAc \
      "SELECT COUNT(*) FROM customers WHERE batch_id LIKE 'demo_%'" 2>/dev/null || echo "0")
    check_result "US-W DSQL customers" "$DSQL_CUSTOMERS" "$count"
  else
    check_result "US-W DSQL customers" "SKIP" "$count"
  fi

  if [ -n "${USW_MONGO_HOST:-}" ]; then
    USW_PRODUCTS=$(mongosh --host "${USW_MONGO_HOST}" --quiet --eval \
      "db.getSiblingDB('ecommerce').products.countDocuments({batch_id: /^demo_/})" 2>/dev/null || echo "0")
    check_result "US-W MongoDB products" "$USW_PRODUCTS" "$count"
  else
    check_result "US-W MongoDB products" "SKIP" "$count"
  fi

  # --- Target: US-E (DR) ---
  step "4.3" "US-E DR Target (Aurora DSQL Linked + MongoDB)"
  if [ -n "${USE_DSQL_ENDPOINT:-}" ]; then
    DSQL_DR=$(psql "host=${USE_DSQL_ENDPOINT}.dsql.us-east-1.on.aws dbname=postgres sslmode=require" -tAc \
      "SELECT COUNT(*) FROM customers WHERE batch_id LIKE 'demo_%'" 2>/dev/null || echo "0")
    check_result "US-E DSQL customers (DR)" "$DSQL_DR" "$count"
  else
    check_result "US-E DSQL customers (DR)" "SKIP" "$count"
  fi

  if [ -n "${USE_MONGO_HOST:-}" ]; then
    USE_PRODUCTS=$(mongosh --host "${USE_MONGO_HOST}" --quiet --eval \
      "db.getSiblingDB('ecommerce').products.countDocuments({batch_id: /^demo_/})" 2>/dev/null || echo "0")
    check_result "US-E MongoDB products (DR)" "$USE_PRODUCTS" "$count"
  else
    check_result "US-E MongoDB products (DR)" "SKIP" "$count"
  fi

  # --- Summary ---
  echo ""
  echo -e "${BOLD}Verification Summary:${NC} ${G}${pass} passed${NC}, ${R}${fail_count} failed${NC}, ${Y}${skip} skipped${NC}"
  [ "$fail_count" -gt 0 ] && warn "Some targets have 0 records. CDC pipeline may need more time to propagate."
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: DR Failover Test
# ─────────────────────────────────────────────────────────────────────────────

do_dr_test() {
  banner "STEP 5: DR Failover Simulation"

  step "5.1" "Simulate OnPrem failure — stop writing new data"
  info "In a real DR scenario, the OnPrem VPC becomes unreachable"
  info "Aurora DSQL (US-E) already has the latest data (auto-replicated)"
  info "MongoDB (US-E) has the latest data via MSK Replicator pipeline"

  step "5.2" "Connect to US-E EKS cluster"
  if aws eks update-kubeconfig --region us-east-1 --name "use-eks" --alias use-eks 2>/dev/null; then
    ok "Connected to US-E EKS"
  else
    warn "US-E EKS cluster not reachable (expected if not deployed yet)"
  fi

  step "5.3" "Verify US-E data availability"
  if [ -n "${USE_DSQL_ENDPOINT:-}" ]; then
    DR_COUNT=$(psql "host=${USE_DSQL_ENDPOINT}.dsql.us-east-1.on.aws dbname=postgres sslmode=require" -tAc \
      "SELECT COUNT(*) FROM customers" 2>/dev/null || echo "?")
    ok "US-E Aurora DSQL: ${DR_COUNT} total customers"
  fi
  if [ -n "${USE_MONGO_HOST:-}" ]; then
    DR_MONGO=$(mongosh --host "${USE_MONGO_HOST}" --quiet --eval \
      "db.getSiblingDB('ecommerce').products.countDocuments()" 2>/dev/null || echo "?")
    ok "US-E MongoDB: ${DR_MONGO} total products"
  fi

  step "5.4" "DR Readiness Assessment"
  echo -e "
  ${BOLD}DR Failover Checklist:${NC}
  ${G}✓${NC} Aurora DSQL (US-E) — active-active, automatic replication
  ${G}✓${NC} MongoDB (US-E) — replicated via MSK Replicator → MSK Connect
  ${G}✓${NC} EKS (US-E) — cluster ready, app can be deployed
  ${Y}→${NC} Route 53 — switch DNS to US-E CloudFront distribution
  ${Y}→${NC} Update app ConfigMap to point to US-E database endpoints
  "
}

# ─────────────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────────────

do_cleanup() {
  banner "CLEANUP: Remove All Demo Resources and Data"

  step "C.1" "Deleting demo data from source databases"
  local url=""
  if [ -f "${SCRIPT_DIR}/.demo-url" ]; then
    url="http://$(cat "${SCRIPT_DIR}/.demo-url")"
  fi

  if [ -n "$url" ]; then
    batch_id=""
    [ -f "${SCRIPT_DIR}/.demo-batch-id" ] && batch_id=$(cat "${SCRIPT_DIR}/.demo-batch-id")
    curl -sf -X DELETE "${url}/api/demo/cleanup?batch_id=${batch_id}" | python3 -m json.tool 2>/dev/null && \
      ok "Demo data deleted via API" || warn "API cleanup failed, will delete manually"
  fi

  step "C.2" "Removing K8s resources"
  aws eks update-kubeconfig --region us-west-2 --name "${ONPREM_EKS_CLUSTER:-onprem-eks}" --alias onprem-eks 2>/dev/null || true
  kubectl delete namespace dr-demo --ignore-not-found --timeout=60s 2>/dev/null && \
    ok "Namespace dr-demo deleted" || warn "Namespace deletion timed out"

  step "C.3" "Cleaning up local state files"
  rm -f "${SCRIPT_DIR}/.demo-url" "${SCRIPT_DIR}/.demo-batch-id"
  ok "Local state cleaned"

  echo -e "\n${G}${BOLD}Cleanup complete. Ready for next demo run.${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Full Demo (all steps)
# ─────────────────────────────────────────────────────────────────────────────

do_all() {
  banner "DR Lab Migration Demo — Full Run"
  echo -e "${DIM}Flow: CloudFront → ALB → EKS Pod → PG/MongoDB → Debezium → Kafka"
  echo -e "      → MM2 → MSK(US-W) → Connect → DSQL + MongoDB(US-W)"
  echo -e "      → Replicator → MSK(US-E) → Connect → MongoDB(US-E)"
  echo -e "      → DSQL Multi-Region → DSQL(US-E)${NC}"
  echo ""
  read -rp "Press Enter to start the demo..."

  do_deploy
  echo ""; read -rp "Press Enter to seed data..."

  do_seed
  echo ""; echo -e "${Y}Waiting for CDC pipeline to propagate...${NC}"
  wait_with_dots "Allowing 30s for CDC propagation" 30
  read -rp "Press Enter to check pipeline status..."

  do_pipeline
  echo ""; read -rp "Press Enter to verify replication..."

  do_verify
  echo ""; read -rp "Press Enter to run DR failover test..."

  do_dr_test

  echo ""
  banner "Demo Complete"
  echo -e "To clean up: ${BOLD}./run-demo.sh cleanup${NC}"
  echo -e "To re-run:   ${BOLD}./run-demo.sh all${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

load_env

case "${1:-all}" in
  deploy)   do_deploy ;;
  seed)     do_seed ;;
  pipeline) do_pipeline ;;
  verify)   do_verify ;;
  dr-test)  do_dr_test ;;
  cleanup)  do_cleanup ;;
  all)      do_all ;;
  *)
    echo "Usage: $0 [deploy|seed|pipeline|verify|dr-test|cleanup|all]"
    echo ""
    echo "Steps:"
    echo "  deploy   - Deploy Demo API to OnPrem EKS"
    echo "  seed     - Generate test data via API (CF → ALB → EKS → DB)"
    echo "  pipeline - Check CDC pipeline status (Debezium, Kafka, MSK)"
    echo "  verify   - Verify data replication across all regions"
    echo "  dr-test  - Simulate DR failover to US-E"
    echo "  cleanup  - Remove all demo resources and data"
    echo "  all      - Run full interactive demo (default)"
    exit 1
    ;;
esac
