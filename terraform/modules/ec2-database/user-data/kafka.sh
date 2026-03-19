#!/bin/bash
set -e
dnf update -y && dnf install -y java-17-amazon-corretto
KAFKA_VERSION=3.7.0
curl -sL "https://downloads.apache.org/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz" | tar xz -C /opt
ln -s /opt/kafka_2.13-$KAFKA_VERSION /opt/kafka
# Configure broker
cat > /opt/kafka/config/server.properties << 'KAFKACFG'
broker.id=${broker_id}
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://${private_ip}:9092
log.dirs=/var/kafka-logs
num.partitions=6
default.replication.factor=3
min.insync.replicas=2
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
log.retention.hours=168
zookeeper.connect=${zookeeper_connect}
KAFKACFG
mkdir -p /var/kafka-logs
# Systemd service for Kafka
cat > /etc/systemd/system/kafka.service << 'SVC'
[Unit]
Description=Apache Kafka
After=network.target
[Service]
Type=simple
User=root
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable kafka && systemctl start kafka
