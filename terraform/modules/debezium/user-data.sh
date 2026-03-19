#!/bin/bash
set -e
dnf update -y && dnf install -y java-17-amazon-corretto
KAFKA_VERSION=3.7.0
DEBEZIUM_VERSION=2.7.0.Final
# Install Kafka Connect
curl -sL "https://downloads.apache.org/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz" | tar xz -C /opt
ln -s /opt/kafka_2.13-$KAFKA_VERSION /opt/kafka
# Download Debezium connectors
mkdir -p /opt/kafka/connect-plugins
cd /opt/kafka/connect-plugins
curl -sL "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/$DEBEZIUM_VERSION/debezium-connector-postgres-$DEBEZIUM_VERSION-plugin.tar.gz" | tar xz
curl -sL "https://repo1.maven.org/maven2/io/debezium/debezium-connector-mongodb/$DEBEZIUM_VERSION/debezium-connector-mongodb-$DEBEZIUM_VERSION-plugin.tar.gz" | tar xz
# Configure Kafka Connect distributed mode
cat > /opt/kafka/config/connect-distributed.properties << 'PROPS'
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
PROPS
# Systemd service
cat > /etc/systemd/system/kafka-connect.service << 'SVC'
[Unit]
Description=Kafka Connect
After=network.target
[Service]
Type=simple
User=root
ExecStart=/opt/kafka/bin/connect-distributed.sh /opt/kafka/config/connect-distributed.properties
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable kafka-connect && systemctl start kafka-connect
