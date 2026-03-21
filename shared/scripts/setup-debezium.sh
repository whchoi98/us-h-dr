#!/bin/bash
set -e
DEBEZIUM_HOST=${1:?Usage: $0 <debezium-host> <postgres-host> <mongo-host> <kafka-brokers>}
POSTGRES_HOST=${2:?}
MONGO_HOST=${3:?}
KAFKA_BROKERS=${4:?}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:?Error: POSTGRES_PASSWORD env var must be set}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../configs"

echo "=== Registering Debezium PostgreSQL Source Connector ==="
PG_CONFIG=$(cat "$CONFIG_DIR/debezium-postgres-source.json" | \
  sed "s|\${POSTGRES_HOST}|$POSTGRES_HOST|g" | \
  sed "s|\${POSTGRES_PASSWORD}|$POSTGRES_PASSWORD|g" | \
  sed "s|\${KAFKA_BROKERS}|$KAFKA_BROKERS|g")
curl -sf -X POST "http://$DEBEZIUM_HOST:8083/connectors" \
  -H "Content-Type: application/json" \
  -d "$PG_CONFIG" | jq .
echo "PostgreSQL connector registered."

echo ""
echo "=== Registering Debezium MongoDB Source Connector ==="
MONGO_CONFIG=$(cat "$CONFIG_DIR/debezium-mongodb-source.json" | \
  sed "s|\${MONGO_HOST}|$MONGO_HOST|g")
curl -sf -X POST "http://$DEBEZIUM_HOST:8083/connectors" \
  -H "Content-Type: application/json" \
  -d "$MONGO_CONFIG" | jq .
echo "MongoDB connector registered."

echo ""
echo "=== Checking connector status ==="
sleep 5
curl -sf "http://$DEBEZIUM_HOST:8083/connectors/postgres-source/status" | jq .
curl -sf "http://$DEBEZIUM_HOST:8083/connectors/mongodb-source/status" | jq .
echo "Done."
