#!/bin/bash
set -e
dnf update -y && dnf install -y java-17-amazon-corretto
KAFKA_VERSION=3.7.0
curl -sL "https://archive.apache.org/dist/kafka/$KAFKA_VERSION/kafka_2.13-$KAFKA_VERSION.tgz" -o /tmp/kafka.tgz
tar xzf /tmp/kafka.tgz -C /opt
ln -sf /opt/kafka_2.13-$KAFKA_VERSION /opt/kafka
rm -f /tmp/kafka.tgz
mkdir -p /var/kafka-logs

# Get private IP dynamically
PRIV_IP=$(hostname -I | awk '{print $1}')

# KRaft configuration (no ZooKeeper)
cat > /opt/kafka/config/kraft/server.properties << KAFKACFG
process.roles=broker,controller
node.id=${broker_id}
controller.quorum.voters=${quorum_voters}
listeners=PLAINTEXT://$PRIV_IP:9092,CONTROLLER://$PRIV_IP:9093
advertised.listeners=PLAINTEXT://$PRIV_IP:9092
controller.listener.names=CONTROLLER
inter.broker.listener.name=PLAINTEXT
log.dirs=/var/kafka-logs
num.partitions=6
default.replication.factor=3
min.insync.replicas=2
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
log.retention.hours=168
auto.create.topics.enable=true
KAFKACFG

# Format storage with cluster ID
/opt/kafka/bin/kafka-storage.sh format -t ${cluster_id} \
  -c /opt/kafka/config/kraft/server.properties --ignore-formatted

# Systemd service
cat > /etc/systemd/system/kafka.service << 'SVC'
[Unit]
Description=Apache Kafka (KRaft)
After=network.target
[Service]
Type=simple
User=root
Environment=KAFKA_HEAP_OPTS=-Xmx2G -Xms2G
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/kraft/server.properties
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload && systemctl enable kafka && systemctl start kafka
