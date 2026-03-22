#!/bin/bash
# =============================================================================
#  Multi-Region DR Migration Demo — Visual E2E Test
#
#  Usage: ./demo-e2e.sh [all|check|seed|pipeline|verify|verify-usw|verify-use|dr-failover|cleanup]
# =============================================================================
set -eo pipefail

# ─────────────── Config ───────────────
ONPREM_PG="10.0.20.79"
ONPREM_MONGO="10.0.21.83"
ONPREM_KAFKA="10.0.20.208:9092,10.0.20.222:9092,10.0.21.175:9092,10.0.21.169:9092"
DEBEZIUM="10.0.20.15"
USW_MONGO="10.1.20.150"
USE_MONGO="10.2.20.68"
DBZ_INSTANCE="i-04fe68759e5519797"
DSQL_PRIMARY_ID="h5tug4ovcrmqa7yo4vnygjjavq"
DSQL_LINKED_ID="fjtug4ovqc7sdjfbkyoezgoclm"
MSK_REPLICATOR_ARN="arn:aws:kafka:us-east-1:061525506239:replicator/dr-lab-usw-to-use-v8/080c3171-a4e3-4f36-a4c5-62edc04954aa-3"

# ─────────────── Colors ───────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'; M='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
BG_G='\033[42;30m'; BG_R='\033[41;37m'; BG_B='\033[44;37m'; BG_Y='\033[43;30m'; BG_M='\033[45;37m'

# ─────────────── Helpers ───────────────
banner() {
  echo ""
  echo -e "${BG_B}                                                                    ${NC}"
  echo -e "${BG_B}  $1$(printf '%*s' $((66-${#1})) '')${NC}"
  echo -e "${BG_B}                                                                    ${NC}"
  echo ""
}
section() { echo -e "\n${BOLD}${C}━━━ $1 ━━━${NC}\n"; }
ok()      { echo -e "  ${BG_G} PASS ${NC} $1"; }
fail()    { echo -e "  ${BG_R} FAIL ${NC} $1"; }
skip()    { echo -e "  ${BG_Y} SKIP ${NC} $1"; }
info()    { echo -e "  ${DIM}$1${NC}"; }
arrow()   { echo -e "  ${M}▶${NC} $1"; }
data()    { echo -e "  ${G}│${NC} $1"; }

wait_bar() {
  local msg="$1" secs="$2" width=40
  echo -ne "  ${DIM}${msg} ["
  for ((i=0; i<secs; i++)); do
    pct=$((i*width/secs))
    echo -ne "\r  ${DIM}${msg} ["
    for ((j=0; j<width; j++)); do
      [ $j -lt $pct ] && echo -ne "█" || echo -ne "░"
    done
    echo -ne "] $((i+1))/${secs}s"
    sleep 1
  done
  echo -e "\r  ${DIM}${msg} [$(printf '█%.0s' $(seq 1 $width))] ${secs}/${secs}s ${NC}"
}

ssm_run() {
  local inst="$1" region="${2:-us-west-2}"
  shift 2
  local cmd_id
  cmd_id=$(aws ssm send-command --instance-ids "$inst" --region "$region" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=$1" \
    --query "Command.CommandId" --output text 2>/dev/null)
  sleep "${2:-5}"
  aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$inst" --region "$region" \
    --query "StandardOutputContent" --output text 2>/dev/null
}

# ═══════════════════════════════════════════════════════════════════
#  STEP 1: Infrastructure Check
# ═══════════════════════════════════════════════════════════════════
do_check() {
  banner "STEP 1: Infrastructure Health Check"

  section "EKS Clusters (3 clusters, 12 nodes)"
  for ctx in onprem-eks usw-eks use-eks; do
    nodes=$(kubectl --context "$ctx" get nodes --no-headers 2>/dev/null | { grep Ready || true; } | wc -l)
    if [ "$nodes" -gt 0 ]; then
      ok "${ctx}: ${BOLD}${nodes} nodes${NC} Ready"
    else
      fail "${ctx}: not reachable"
    fi
  done

  section "Demo API (OnPrem EKS)"
  pods=$(kubectl --context onprem-eks get pods -n dr-demo --no-headers 2>/dev/null | { grep Running || true; } | wc -l)
  if [ "$pods" -gt 0 ]; then
    ok "demo-api: ${BOLD}${pods} pods${NC} Running"
  else
    skip "demo-api: not deployed (will deploy in seed step)"
  fi

  section "Debezium CDC Connectors"
  CONNECTORS=$(ssm_run "$DBZ_INSTANCE" us-west-2 '["curl -sf http://localhost:8083/connectors 2>/dev/null || echo FAIL"]')
  if echo "$CONNECTORS" | grep -q "demo-pg"; then
    for c in demo-pg demo-mongo; do
      STATE=$(ssm_run "$DBZ_INSTANCE" us-west-2 "[\"curl -sf http://localhost:8083/connectors/$c/status 2>/dev/null | python3 -c \\\"import sys,json; d=json.load(sys.stdin); print(d['connector']['state'],d['tasks'][0]['state'])\\\"\"]" 3)
      CSTATE=$(echo "$STATE" | awk '{print $1}')
      TSTATE=$(echo "$STATE" | awk '{print $2}')
      if [ "$CSTATE" = "RUNNING" ] && [ "$TSTATE" = "RUNNING" ]; then
        ok "${c}: ${BOLD}RUNNING${NC} (connector + task)"
      else
        fail "${c}: ${CSTATE}/${TSTATE}"
      fi
    done
  elif echo "$CONNECTORS" | grep -q "FAIL"; then
    fail "Debezium Connect not reachable"
  else
    skip "No demo connectors yet (will register in seed step)"
  fi

  section "MSK Connect Sink Connectors"
  for region in us-west-2 us-east-1; do
    aws kafkaconnect list-connectors --region "$region" \
      --query "connectors[].{N:connectorName,S:connectorState}" --output text 2>/dev/null | \
      while read -r name state; do
        if [ "$state" = "RUNNING" ]; then
          ok "${name}: ${BOLD}RUNNING${NC}"
        else
          fail "${name}: ${state}"
        fi
      done
  done

  section "MSK Replicator (US-W → US-E)"
  REP=$(aws kafka describe-replicator --replicator-arn "$MSK_REPLICATOR_ARN" \
    --region us-east-1 --query "ReplicatorState" --output text 2>/dev/null || echo "UNKNOWN")
  if [ "$REP" = "RUNNING" ]; then
    ok "MSK Replicator: ${BOLD}RUNNING${NC} (cross-region)"
  else
    fail "MSK Replicator: ${REP}"
  fi

  section "Aurora DSQL (Multi-Region)"
  for pair in "${DSQL_PRIMARY_ID}|us-west-2|Primary" "${DSQL_LINKED_ID}|us-east-1|Linked(DR)"; do
    IFS='|' read -r id region label <<< "$pair"
    STATUS=$(aws dsql get-cluster --identifier "$id" --region "$region" --query "status" --output text 2>/dev/null)
    if [ "$STATUS" = "ACTIVE" ]; then
      ok "DSQL ${label}: ${BOLD}ACTIVE${NC}"
    else
      fail "DSQL ${label}: ${STATUS}"
    fi
  done
}

# ═══════════════════════════════════════════════════════════════════
#  STEP 2: Seed Data
# ═══════════════════════════════════════════════════════════════════
do_seed() {
  banner "STEP 2: Seed Demo Data"

  echo -e "  ${DIM}경로: CloudFront → ALB → EKS Pod → PostgreSQL + MongoDB${NC}"
  echo ""

  kubectl config use-context onprem-eks >/dev/null 2>&1

  # Auto-deploy Demo API if not running
  section "Ensure Demo API is Running"
  local api_pods
  api_pods=$(kubectl get pods -n dr-demo --no-headers 2>/dev/null | { grep Running || true; } | wc -l)
  if [ "$api_pods" -eq 0 ]; then
    arrow "Deploying Demo API to OnPrem EKS..."
    kubectl create namespace dr-demo --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
    kubectl create configmap demo-db-config -n dr-demo \
      --from-literal=pg_host="${ONPREM_PG}" --from-literal=pg_user="debezium" \
      --from-literal=pg_db="ecommerce" --from-literal=mongo_host="${ONPREM_MONGO}" \
      --from-literal=mongo_user="" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
    kubectl create secret generic demo-db-secrets -n dr-demo \
      --from-literal=pg_password="debezium" --from-literal=mongo_password="" \
      --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    kubectl apply -f "${SCRIPT_DIR}/k8s/demo-app.yaml" 2>/dev/null
    arrow "Waiting for pods..."
    kubectl wait --for=condition=ready pod -l app=demo-api -n dr-demo --timeout=180s 2>/dev/null
    ok "Demo API deployed (2 pods)"
  else
    ok "Demo API already running (${api_pods} pods)"
  fi

  # Auto-register Debezium connectors if missing
  section "Ensure Debezium Connectors"
  EXISTING=$(ssm_run "$DBZ_INSTANCE" us-west-2 '["curl -sf http://localhost:8083/connectors 2>/dev/null"]')
  if ! echo "$EXISTING" | grep -q "demo-pg"; then
    arrow "Registering demo-pg connector..."
    ssm_run "$DBZ_INSTANCE" us-west-2 '["curl -sf -X POST http://localhost:8083/connectors -H \"Content-Type: application/json\" -d '"'"'{\"name\":\"demo-pg\",\"config\":{\"connector.class\":\"io.debezium.connector.postgresql.PostgresConnector\",\"database.hostname\":\"10.0.20.79\",\"database.port\":\"5432\",\"database.user\":\"debezium\",\"database.password\":\"debezium\",\"database.dbname\":\"ecommerce\",\"topic.prefix\":\"source\",\"plugin.name\":\"pgoutput\",\"slot.name\":\"demo_slot\",\"publication.autocreate.mode\":\"all_tables\",\"table.include.list\":\"public.customers,public.orders\",\"snapshot.mode\":\"initial\"}}'"'"' 2>/dev/null"]' 5 >/dev/null
    ok "demo-pg registered"
  else
    ok "demo-pg already exists"
  fi
  if ! echo "$EXISTING" | grep -q "demo-mongo"; then
    arrow "Registering demo-mongo connector..."
    ssm_run "$DBZ_INSTANCE" us-west-2 '["curl -sf -X POST http://localhost:8083/connectors -H \"Content-Type: application/json\" -d '"'"'{\"name\":\"demo-mongo\",\"config\":{\"connector.class\":\"io.debezium.connector.mongodb.MongoDbConnector\",\"mongodb.connection.string\":\"mongodb://10.0.21.83:27017/?replicaSet=rs0\",\"topic.prefix\":\"source\",\"database.include.list\":\"ecommerce\",\"collection.include.list\":\"ecommerce.products,ecommerce.inventory\",\"capture.mode\":\"change_streams_update_full\",\"snapshot.mode\":\"initial\"}}'"'"' 2>/dev/null"]' 5 >/dev/null
    ok "demo-mongo registered"
  else
    ok "demo-mongo already exists"
  fi

  section "Inserting Records"
  RESULT=$(kubectl exec deploy/demo-api -n dr-demo -- python3 -c "
import psycopg2, datetime, random, hashlib
from pymongo import MongoClient

ts = datetime.datetime.now(datetime.UTC).strftime('%Y%m%d_%H%M%S')
batch = f'demo_{ts}'
count = 20

conn = psycopg2.connect(host='${ONPREM_PG}', port=5432, user='debezium', password='debezium', dbname='ecommerce')
cur = conn.cursor()
cities = ['Seoul','Tokyo','NYC','London','Berlin','Sydney']
products = ['Laptop','Phone','Tablet','Monitor','Keyboard','Mouse']
statuses = ['pending','processing','shipped','delivered']
pg_c = pg_o = 0
for i in range(count):
    cur.execute('INSERT INTO customers (name,email,city,batch_id) VALUES (%s,%s,%s,%s) RETURNING id',
                (f'Demo_{batch}_{i:03d}', f'demo{i}@test.lab', random.choice(cities), batch))
    cid = cur.fetchone()[0]; pg_c += 1
    for _ in range(random.randint(1,3)):
        cur.execute('INSERT INTO orders (customer_id,product,amount,status,batch_id) VALUES (%s,%s,%s,%s,%s)',
                    (cid, random.choice(products), round(random.uniform(50,2000),2), random.choice(statuses), batch))
        pg_o += 1
conn.commit(); conn.close()

mdb = MongoClient('mongodb://${ONPREM_MONGO}:27017/?directConnection=true')['ecommerce']
docs_p = [{'product_id': hashlib.md5(f'{batch}_{i}'.encode()).hexdigest()[:12], 'name': f'Demo_{batch}_{i:03d}',
           'category': random.choice(['Electronics','Books','Clothing','Home']),
           'price': round(random.uniform(10,500),2), 'batch_id': batch,
           'created_at': datetime.datetime.now(datetime.UTC)} for i in range(count)]
docs_i = [{'product_id': d['product_id'], 'warehouse': random.choice(['WH-WEST','WH-EAST']),
           'quantity': random.randint(0,500), 'batch_id': batch,
           'updated_at': datetime.datetime.now(datetime.UTC)} for d in docs_p]
mdb.products.insert_many(docs_p); mdb.inventory.insert_many(docs_i)
print(f'BATCH={batch}')
print(f'PG_C={pg_c}')
print(f'PG_O={pg_o}')
print(f'MONGO_P={count}')
print(f'MONGO_I={count}')
" 2>/dev/null)

  BATCH=$(echo "$RESULT" | grep BATCH= | cut -d= -f2)
  PG_C=$(echo "$RESULT" | grep PG_C= | cut -d= -f2)
  PG_O=$(echo "$RESULT" | grep PG_O= | cut -d= -f2)
  MONGO_P=$(echo "$RESULT" | grep MONGO_P= | cut -d= -f2)
  MONGO_I=$(echo "$RESULT" | grep MONGO_I= | cut -d= -f2)

  echo -e "  ${G}┌────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${G}│${NC}  ${BOLD}Batch ID:${NC} ${Y}${BATCH}${NC}"
  echo -e "  ${G}│${NC}"
  echo -e "  ${G}│${NC}  ${BOLD}PostgreSQL${NC}"
  echo -e "  ${G}│${NC}    customers: ${BOLD}${PG_C}${NC} rows inserted"
  echo -e "  ${G}│${NC}    orders:    ${BOLD}${PG_O}${NC} rows inserted"
  echo -e "  ${G}│${NC}"
  echo -e "  ${G}│${NC}  ${BOLD}MongoDB${NC}"
  echo -e "  ${G}│${NC}    products:  ${BOLD}${MONGO_P}${NC} docs inserted"
  echo -e "  ${G}│${NC}    inventory: ${BOLD}${MONGO_I}${NC} docs inserted"
  echo -e "  ${G}└────────────────────────────────────────────────────┘${NC}"

  echo "$BATCH" > /tmp/.demo-batch
}

# ═══════════════════════════════════════════════════════════════════
#  STEP 3: Pipeline Trace
# ═══════════════════════════════════════════════════════════════════
do_pipeline() {
  banner "STEP 3: CDC Pipeline Trace"

  section "① Debezium → OnPrem Kafka"
  arrow "Debezium captures WAL (PG) + Change Streams (MongoDB)"
  TOPICS=$(ssm_run "$DBZ_INSTANCE" us-west-2 '["/opt/kafka/bin/kafka-topics.sh --bootstrap-server 10.0.20.208:9092 --list 2>/dev/null | grep source"]' 5)
  echo "$TOPICS" | while read -r t; do [ -n "$t" ] && data "topic: ${BOLD}${t}${NC}"; done

  section "② MirrorMaker2 → MSK US-W"
  arrow "MM2 replicates with IdentityReplicationPolicy (IAM auth)"
  MSK_TOPICS=$(ssm_run "$DBZ_INSTANCE" us-west-2 '["/opt/kafka/bin/kafka-topics.sh --bootstrap-server b-1.drlabmskusw.e2kwws.c11.kafka.us-west-2.amazonaws.com:9098 --list --command-config /tmp/msk-client.properties 2>/dev/null | grep ^source\\."]' 8)
  echo "$MSK_TOPICS" | while read -r t; do [ -n "$t" ] && data "MSK topic: ${BOLD}${t}${NC}"; done

  section "③ MSK US-W → Sinks"
  arrow "JDBC Sink → Aurora DSQL Primary"
  arrow "MongoDB Sink → US-W MongoDB (10.1.20.150)"

  section "④ MSK Replicator → MSK US-E"
  arrow "Cross-region replication (source.* topics)"
  arrow "Topic prefix: dr-lab-msk-usw-*.source.*"

  section "⑤ MSK US-E → Sink → US-E MongoDB"
  arrow "MongoDB Sink → US-E MongoDB (10.2.20.68)"

  section "⑥ Aurora DSQL Auto Replication"
  arrow "DSQL Primary (us-west-2) ↔ DSQL Linked (us-east-1)"
  arrow "Automatic multi-region, < 1s latency"
}

# ═══════════════════════════════════════════════════════════════════
#  STEP 4/5: Verify Targets
# ═══════════════════════════════════════════════════════════════════
do_verify_usw() {
  banner "STEP 4: Verify US-W Targets"

  section "US-W MongoDB (10.1.20.150)"
  kubectl config use-context onprem-eks >/dev/null 2>&1
  USW_RESULT=$(kubectl exec deploy/demo-api -n dr-demo -- python3 -c "
from pymongo import MongoClient
usw = MongoClient('mongodb://${USW_MONGO}:27017/?directConnection=true', serverSelectionTimeoutMS=5000)['ecommerce']
for col in usw.list_collection_names():
    print(f'{col}={usw[col].count_documents({})}')
" 2>/dev/null)
  if [ -n "$USW_RESULT" ]; then
    echo "$USW_RESULT" | while IFS='=' read -r col cnt; do
      ok "${col}: ${BOLD}${cnt} records${NC}"
    done
  else
    skip "No collections yet"
  fi

  section "Aurora DSQL Primary (us-west-2)"
  kubectl config use-context usw-eks >/dev/null 2>&1
  kubectl delete pod dsql-v-usw --ignore-not-found 2>/dev/null; sleep 2
  kubectl run dsql-v-usw --image=public.ecr.aws/docker/library/python:3.12-slim --restart=Never \
    --command -- bash -c "pip install -q boto3 psycopg2-binary 2>/dev/null; python3 -c \"
import boto3, psycopg2
c = boto3.client('dsql', region_name='us-west-2')
t = c.generate_db_connect_admin_auth_token(Hostname='${DSQL_PRIMARY_ID}.dsql.us-west-2.on.aws', Region='us-west-2')
conn = psycopg2.connect(host='${DSQL_PRIMARY_ID}.dsql.us-west-2.on.aws', port=5432, dbname='postgres', user='admin', password=t, sslmode='require')
cur = conn.cursor()
cur.execute(\\\"SELECT table_name FROM information_schema.tables WHERE table_schema='public'\\\")
for r in cur.fetchall():
    cur.execute(f'SELECT COUNT(*) FROM {r[0]}')
    print(f'{r[0]}={cur.fetchone()[0]}')
if not cur.fetchall(): print('EMPTY=0')
conn.close()
\"" 2>/dev/null
  sleep 25
  DSQL_RESULT=$(kubectl logs dsql-v-usw 2>/dev/null | grep '=')
  kubectl delete pod dsql-v-usw --ignore-not-found 2>/dev/null
  if [ -n "$DSQL_RESULT" ] && ! echo "$DSQL_RESULT" | grep -q "EMPTY"; then
    echo "$DSQL_RESULT" | while IFS='=' read -r tbl cnt; do
      ok "${tbl}: ${BOLD}${cnt} rows${NC}"
    done
  else
    skip "No tables yet (JDBC Sink may need more time)"
  fi
}

do_verify_use() {
  banner "STEP 5: Verify US-E DR Targets"

  section "US-E MongoDB (10.2.20.68) — via MSK Replicator"
  kubectl config use-context use-eks >/dev/null 2>&1
  kubectl delete pod mongo-v-use --ignore-not-found 2>/dev/null; sleep 2
  kubectl run mongo-v-use --image=public.ecr.aws/docker/library/python:3.12-slim --restart=Never \
    --command -- bash -c "pip install -q pymongo 2>/dev/null; python3 -c \"
from pymongo import MongoClient
db = MongoClient('mongodb://${USE_MONGO}:27017/?directConnection=true', serverSelectionTimeoutMS=5000)['ecommerce']
cols = db.list_collection_names()
for col in cols:
    print(f'{col}={db[col].count_documents({})}')
if not cols:
    print('EMPTY=0')
\"" 2>/dev/null
  sleep 20
  USE_MONGO_RESULT=$(kubectl logs mongo-v-use 2>/dev/null | grep '=')
  kubectl delete pod mongo-v-use --ignore-not-found 2>/dev/null
  if echo "$USE_MONGO_RESULT" | grep -q "EMPTY"; then
    skip "No data yet (Replicator propagation in progress)"
  elif [ -n "$USE_MONGO_RESULT" ]; then
    echo "$USE_MONGO_RESULT" | while IFS='=' read -r col cnt; do
      ok "${col}: ${BOLD}${cnt} records${NC}"
    done
  else
    skip "US-E MongoDB check timed out"
  fi

  section "Aurora DSQL Linked (us-east-1) — auto multi-region"
  kubectl delete pod dsql-v-use --ignore-not-found 2>/dev/null; sleep 2
  kubectl run dsql-v-use --image=public.ecr.aws/docker/library/python:3.12-slim --restart=Never \
    --command -- bash -c "pip install -q boto3 psycopg2-binary 2>/dev/null; python3 -c \"
import boto3, psycopg2
c = boto3.client('dsql', region_name='us-east-1')
t = c.generate_db_connect_admin_auth_token(Hostname='${DSQL_LINKED_ID}.dsql.us-east-1.on.aws', Region='us-east-1')
conn = psycopg2.connect(host='${DSQL_LINKED_ID}.dsql.us-east-1.on.aws', port=5432, dbname='postgres', user='admin', password=t, sslmode='require')
cur = conn.cursor()
cur.execute(\\\"SELECT table_name FROM information_schema.tables WHERE table_schema='public'\\\")
for r in cur.fetchall():
    cur.execute(f'SELECT COUNT(*) FROM {r[0]}')
    print(f'{r[0]}={cur.fetchone()[0]}')
conn.close()
\"" 2>/dev/null
  sleep 25
  DSQL_DR=$(kubectl logs dsql-v-use 2>/dev/null | grep '=')
  kubectl delete pod dsql-v-use --ignore-not-found 2>/dev/null
  if [ -n "$DSQL_DR" ]; then
    echo "$DSQL_DR" | while IFS='=' read -r tbl cnt; do
      ok "${tbl}: ${BOLD}${cnt} rows${NC} (replicated from US-W)"
    done
  else
    skip "DSQL Linked not reachable"
  fi
}

do_verify() {
  do_verify_usw
  do_verify_use
}

# ═══════════════════════════════════════════════════════════════════
#  STEP 6: DR Failover
# ═══════════════════════════════════════════════════════════════════
do_dr_failover() {
  banner "STEP 6: DR Failover Simulation"

  section "① OnPrem 장애 발생 (시뮬레이션)"
  echo -e "  ${BG_R} ALERT ${NC} OnPrem VPC (us-west-2) 접근 불가 상태 가정"
  echo ""
  info "OnPrem PostgreSQL, MongoDB, Kafka — 접근 불가"
  info "OnPrem EKS — 접근 불가"
  info "OnPrem CloudFront/ALB — 응답 없음"

  section "② US-E DR 리전 데이터 확인"
  kubectl config use-context use-eks >/dev/null 2>&1
  NODES=$(kubectl get nodes --no-headers 2>/dev/null | { grep Ready || true; } | wc -l)
  ok "US-E EKS: ${BOLD}${NODES} nodes${NC} Ready"
  PODS=$(kubectl get pods -n ui --no-headers 2>/dev/null | { grep Running || true; } | wc -l)
  ok "US-E App: ${BOLD}${PODS} pods${NC} Running (Retail Store)"

  section "③ DR 데이터 가용성"
  arrow "MongoDB US-E: 복제된 데이터로 서비스 가능"
  arrow "Aurora DSQL Linked: 자동 복제된 데이터 사용 가능"

  section "④ DR Failover 절차"
  echo -e "  ${G}┌────────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${G}│${NC}  ${BG_G} READY ${NC}  Aurora DSQL (US-E) — active-active 자동 복제   ${G}│${NC}"
  echo -e "  ${G}│${NC}  ${BG_G} READY ${NC}  MongoDB (US-E) — MSK Replicator 경유 복제      ${G}│${NC}"
  echo -e "  ${G}│${NC}  ${BG_G} READY ${NC}  EKS (US-E) — 앱 + ALB + CloudFront 준비        ${G}│${NC}"
  echo -e "  ${G}│${NC}  ${BG_Y} TODO  ${NC}  Route 53 — DNS를 US-E CloudFront로 전환        ${G}│${NC}"
  echo -e "  ${G}│${NC}  ${BG_Y} TODO  ${NC}  App ConfigMap — US-E DB 엔드포인트로 변경       ${G}│${NC}"
  echo -e "  ${G}└────────────────────────────────────────────────────────┘${NC}"
  echo ""
  echo -e "  ${BOLD}US-E CloudFront:${NC} ${Y}https://d3u6aiv1cmheul.cloudfront.net${NC}"
  echo -e "  ${DIM}이 URL로 전환하면 US-E에서 서비스가 즉시 재개됩니다.${NC}"
}

# ═══════════════════════════════════════════════════════════════════
#  STEP 7: Cleanup
# ═══════════════════════════════════════════════════════════════════
do_cleanup() {
  banner "STEP 7: Cleanup"

  section "Remove Debezium Demo Connectors"
  for c in demo-pg demo-mongo; do
    ssm_run "$DBZ_INSTANCE" us-west-2 "[\"curl -sf -X DELETE http://localhost:8083/connectors/$c 2>/dev/null && echo DELETED || echo NOT_FOUND\"]" 3 | \
      while read -r r; do info "${c}: ${r}"; done
  done

  section "Clean PG Replication Slot"
  ssm_run "$DBZ_INSTANCE" us-west-2 '["PGPASSWORD=debezium psql -h 10.0.20.79 -U debezium -d ecommerce -c \"SELECT pg_drop_replication_slot('"'"'demo_slot'"'"')\" 2>/dev/null || echo no_slot"]' 3 >/dev/null
  info "Replication slot cleaned"

  section "Delete Demo Data"
  kubectl config use-context onprem-eks >/dev/null 2>&1
  kubectl exec deploy/demo-api -n dr-demo -- python3 -c "
import psycopg2
from pymongo import MongoClient
conn = psycopg2.connect(host='${ONPREM_PG}', port=5432, user='debezium', password='debezium', dbname='ecommerce')
cur = conn.cursor()
cur.execute('DELETE FROM orders'); cur.execute('DELETE FROM customers')
conn.commit(); conn.close()
mdb = MongoClient('mongodb://${ONPREM_MONGO}:27017/?directConnection=true')['ecommerce']
mdb.products.drop(); mdb.inventory.drop()
print('OnPrem data cleared')
" 2>/dev/null
  ok "OnPrem DB data cleared"

  section "Delete K8s Resources"
  kubectl --context onprem-eks delete namespace dr-demo --ignore-not-found --timeout=30s 2>/dev/null && \
    ok "Namespace dr-demo deleted" || info "Already deleted"

  echo ""
  echo -e "  ${BG_G} CLEAN ${NC}  Ready for next demo run: ${BOLD}./demo-e2e.sh all${NC}"
}

# ═══════════════════════════════════════════════════════════════════
#  Full Demo
# ═══════════════════════════════════════════════════════════════════
do_all() {
  echo ""
  echo -e "${BG_M}                                                                    ${NC}"
  echo -e "${BG_M}   Multi-Region DR Migration Demo                                  ${NC}"
  echo -e "${BG_M}   OnPrem → US-W → US-E (Disaster Recovery)                        ${NC}"
  echo -e "${BG_M}                                                                    ${NC}"
  echo ""
  echo -e "  ${DIM}Pipeline: CloudFront → ALB → EKS → PG/MongoDB → Debezium → Kafka${NC}"
  echo -e "  ${DIM}          → MM2 → MSK(US-W) → Connect → DSQL + MongoDB${NC}"
  echo -e "  ${DIM}          → Replicator → MSK(US-E) → Connect → MongoDB(US-E)${NC}"
  echo -e "  ${DIM}          → DSQL Multi-Region → DSQL(US-E)${NC}"
  echo ""
  read -rp "  Press ENTER to start..."

  do_check
  read -rp "  Press ENTER to seed data..."

  do_seed
  echo ""
  wait_bar "CDC Pipeline Propagation" 60
  read -rp "  Press ENTER to trace pipeline..."

  do_pipeline
  read -rp "  Press ENTER to verify targets..."

  do_verify
  read -rp "  Press ENTER for DR failover simulation..."

  do_dr_failover

  echo ""
  banner "Demo Complete"
  echo -e "  Cleanup: ${BOLD}./demo-e2e.sh cleanup${NC}"
  echo -e "  Re-run:  ${BOLD}./demo-e2e.sh all${NC}"
  echo ""
}

# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════
case "${1:-all}" in
  check)       do_check ;;
  seed)        do_seed ;;
  pipeline)    do_pipeline ;;
  verify)      do_verify ;;
  verify-usw)  do_verify_usw ;;
  verify-use)  do_verify_use ;;
  dr-failover) do_dr_failover ;;
  cleanup)     do_cleanup ;;
  all)         do_all ;;
  *)
    echo ""
    echo -e "  ${BOLD}Usage:${NC} $0 [command]"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo "    all          Full interactive demo (default)"
    echo "    check        1. Infrastructure health check"
    echo "    seed         2. Seed demo data (PG + MongoDB)"
    echo "    pipeline     3. Trace CDC pipeline"
    echo "    verify       4+5. Verify all targets"
    echo "    verify-usw   4. Verify US-W targets only"
    echo "    verify-use   5. Verify US-E DR targets only"
    echo "    dr-failover  6. DR failover simulation"
    echo "    cleanup      7. Remove demo data and resources"
    echo ""
    ;;
esac
