#!/bin/bash
set -e
dnf update -y
# Install MongoDB 7.0
cat > /etc/yum.repos.d/mongodb-org-7.0.repo << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/7.0/aarch64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
EOF
dnf install -y mongodb-org
# Configure for replica set (required for change streams)
cat > /etc/mongod.conf << 'MONGOCFG'
storage:
  dbPath: /var/lib/mongo
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
net:
  port: 27017
  bindIp: 0.0.0.0
replication:
  replSetName: rs0
MONGOCFG
systemctl enable mongod && systemctl start mongod
sleep 5
# Initialize replica set with actual private IP (not localhost)
# Debezium requires the advertised host to be reachable from external nodes
PRIV_IP=$(hostname -I | awk '{print $1}')
mongosh --eval "rs.initiate({_id:'rs0',members:[{_id:0,host:'$${PRIV_IP}:27017'}]})"
