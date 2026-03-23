#!/bin/bash
set -e
dnf update -y && dnf install -y java-17-amazon-corretto
KAFKA_VERSION=3.7.0
DEBEZIUM_VERSION=2.7.0.Final

# Install Kafka (for connect-distributed.sh)
curl -sL "https://archive.apache.org/dist/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz" -o /tmp/kafka.tgz
tar xzf /tmp/kafka.tgz -C /opt
ln -sf /opt/kafka_2.13-$KAFKA_VERSION /opt/kafka
rm -f /tmp/kafka.tgz

# Download Debezium connectors
mkdir -p /opt/kafka/connect-plugins
cd /opt/kafka/connect-plugins
curl -sL "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/$DEBEZIUM_VERSION/debezium-connector-postgres-$DEBEZIUM_VERSION-plugin.tar.gz" | tar xz
curl -sL "https://repo1.maven.org/maven2/io/debezium/debezium-connector-mongodb/$DEBEZIUM_VERSION/debezium-connector-mongodb-$DEBEZIUM_VERSION-plugin.tar.gz" | tar xz

# Download MSK IAM auth library (for MirrorMaker2 → MSK)
curl -sL "https://github.com/aws/aws-msk-iam-auth/releases/download/v2.3.1/aws-msk-iam-auth-2.3.1-all.jar" \
  -o /opt/kafka/libs/aws-msk-iam-auth-2.3.1-all.jar

# Configure Kafka Connect distributed mode
cat > /opt/kafka/config/connect-distributed.properties << PROPS
bootstrap.servers=${kafka_brokers}
group.id=debezium-connect
key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false
offset.storage.topic=connect-offsets
offset.storage.replication.factor=3
config.storage.topic=connect-configs
config.storage.replication.factor=3
status.storage.topic=connect-status
status.storage.replication.factor=3
plugin.path=/opt/kafka/connect-plugins
rest.port=8083
rest.advertised.host.name=$(hostname -I | awk '{print $1}')
PROPS

# Systemd service for Kafka Connect
cat > /etc/systemd/system/kafka-connect.service << 'SVC'
[Unit]
Description=Kafka Connect (Debezium)
After=network.target
[Service]
Type=simple
User=root
Environment=KAFKA_HEAP_OPTS=-Xmx1G -Xms1G
ExecStart=/opt/kafka/bin/connect-distributed.sh /opt/kafka/config/connect-distributed.properties
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable kafka-connect && systemctl start kafka-connect
