#!/bin/bash
set -e
SOURCE_BROKERS=${1:?Usage: $0 <source-brokers> <target-msk-brokers>}
TARGET_BROKERS=${2:?}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../configs"
MM2_CONFIG="/tmp/mm2-runtime.properties"

echo "=== Configuring MirrorMaker 2 ==="
cat "$CONFIG_DIR/mirrormaker2.properties" | \
  sed "s|\${SOURCE_BOOTSTRAP_SERVERS}|$SOURCE_BROKERS|g" | \
  sed "s|\${TARGET_BOOTSTRAP_SERVERS}|$TARGET_BROKERS|g" > "$MM2_CONFIG"

echo "Source: $SOURCE_BROKERS"
echo "Target: $TARGET_BROKERS"
echo "Starting MirrorMaker 2..."
/opt/kafka/bin/connect-mirror-maker.sh "$MM2_CONFIG"
