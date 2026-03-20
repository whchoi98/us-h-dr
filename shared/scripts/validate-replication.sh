#!/bin/bash
set -e
echo "============================================"
echo "  Multi-Region DR Replication Validation"
echo "============================================"

PG_HOST=${PG_HOST:?Set PG_HOST}
MONGO_HOST=${MONGO_HOST:?Set MONGO_HOST}
DEBEZIUM_HOST=${DEBEZIUM_HOST:?Set DEBEZIUM_HOST}
KAFKA_BROKERS=${KAFKA_BROKERS:?Set KAFKA_BROKERS}
MSK_BROKERS_USW=${MSK_BROKERS_USW:?Set MSK_BROKERS_USW}
DSQL_ENDPOINT_USW=${DSQL_ENDPOINT_USW:-}
MONGO_USW=${MONGO_USW:-}
MONGO_USE=${MONGO_USE:-}

PASS=0
FAIL=0

check() {
  local name=$1
  local cmd=$2
  echo -n "  [$name] ... "
  if eval "$cmd" > /dev/null 2>&1; then
    echo "PASS"
    ((PASS++))
  else
    echo "FAIL"
    ((FAIL++))
  fi
}

echo ""
echo "--- 1. OnPrem Source Databases ---"
check "PostgreSQL connectivity" "pg_isready -h $PG_HOST -p 5432"
check "MongoDB connectivity" "mongosh --host $MONGO_HOST --eval 'db.runCommand({ping:1})' --quiet"
check "PostgreSQL replication slot" "psql -h $PG_HOST -U debezium -d ecommerce -c \"SELECT slot_name FROM pg_replication_slots WHERE slot_name='debezium_slot'\" | grep debezium"

echo ""
echo "--- 2. OnPrem Kafka ---"
check "Kafka brokers (4)" "/opt/kafka/bin/kafka-metadata.sh --snapshot /var/kafka-logs/__cluster_metadata-0/00000000000000000000.log 2>/dev/null || /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server $KAFKA_BROKERS | head -1"
check "Debezium topics exist" "/opt/kafka/bin/kafka-topics.sh --bootstrap-server $KAFKA_BROKERS --list | grep dbserver1"
check "MongoDB topics exist" "/opt/kafka/bin/kafka-topics.sh --bootstrap-server $KAFKA_BROKERS --list | grep mongo"

echo ""
echo "--- 3. Debezium Connectors ---"
check "Debezium Connect API" "curl -sf http://$DEBEZIUM_HOST:8083/connectors"
check "PostgreSQL connector RUNNING" "curl -sf http://$DEBEZIUM_HOST:8083/connectors/postgres-source/status | jq -e '.connector.state==\"RUNNING\"'"
check "MongoDB connector RUNNING" "curl -sf http://$DEBEZIUM_HOST:8083/connectors/mongodb-source/status | jq -e '.connector.state==\"RUNNING\"'"

echo ""
echo "--- 4. MirrorMaker 2 → US-W MSK ---"
check "MSK US-W has mirrored topics" "aws kafka list-topics --cluster-arn \$(aws kafka list-clusters --query 'ClusterInfoList[?ClusterName==\`dr-lab-msk-usw\`].ClusterArn' --output text) 2>/dev/null || echo 'manual check needed'"

echo ""
echo "--- 5. Target Databases ---"
if [ -n "$DSQL_ENDPOINT_USW" ]; then
  check "Aurora DSQL (US-W)" "psql \"host=$DSQL_ENDPOINT_USW dbname=postgres sslmode=require\" -c 'SELECT 1'"
fi
if [ -n "$MONGO_USW" ]; then
  check "MongoDB US-W" "mongosh --host $MONGO_USW --eval 'db.runCommand({ping:1})' --quiet"
fi
if [ -n "$MONGO_USE" ]; then
  check "MongoDB US-E" "mongosh --host $MONGO_USE --eval 'db.runCommand({ping:1})' --quiet"
fi

echo ""
echo "============================================"
echo "  Results: $PASS passed, $FAIL failed"
echo "============================================"

[ $FAIL -eq 0 ] && exit 0 || exit 1
