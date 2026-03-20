# Multi-Region DR Infrastructure - Operational Runbook

## Deployment Order

Follow the phases in spec Section 11:

### Phase 1: Networking
```bash
cd terraform && terraform apply -target=module.onprem_vpc -target=module.usw_center_vpc
terraform apply -target=module.use_center_vpc
terraform apply -target=module.onprem_vpc_endpoints -target=module.usw_vpc_endpoints -target=module.use_vpc_endpoints
terraform apply -target=module.tgw_west -target=module.tgw_east
terraform apply -target=module.tgw_peering
```

### Phase 2: Ingress
```bash
terraform apply -target=module.onprem_ingress -target=module.usw_ingress -target=module.use_ingress
terraform apply -target=module.route53_failover
```

### Phase 3: Compute
```bash
terraform apply -target=module.onprem_eks -target=module.usw_eks -target=module.use_eks
# Create EKS clusters via eksctl
bash shared/scripts/eks-create-cluster.sh shared/configs/eksctl-onprem-eks.yaml
bash shared/scripts/eks-create-cluster.sh shared/configs/eksctl-usw-eks.yaml
bash shared/scripts/eks-create-cluster.sh shared/configs/eksctl-use-eks.yaml
# Deploy VSCode Server
terraform apply -target=module.onprem_vscode
```

### Phase 4: OnPrem Data
```bash
terraform apply -target=module.onprem_data
terraform apply -target=module.onprem_debezium
```

### Phase 5: AWS Data
```bash
terraform apply -target=module.msk_usw -target=module.msk_use
terraform apply -target=module.aurora_dsql
terraform apply -target=module.usw_mongodb -target=module.use_mongodb
```

### Phase 6: Replication
```bash
# Start Debezium connectors
bash shared/scripts/setup-debezium.sh <debezium-ip> <pg-ip> <mongo-ip> <kafka-brokers>
# Wait for topics to appear
sleep 30
# Start MirrorMaker 2 (on MM2 EC2 instance)
bash shared/scripts/setup-mirrormaker2.sh <kafka-brokers> <msk-iam-brokers>
# Deploy MSK Replicator
terraform apply -target=module.msk_replicator
# Deploy MSK Connect sinks
terraform apply -target=module.msk_connect_jdbc_usw
terraform apply -target=module.msk_connect_mongo_usw
terraform apply -target=module.msk_connect_mongo_use
```

### Phase 7: Testing
```bash
# Generate test data from VSCode Server
python3 generate-test-data.py --size 1 --pg-host <pg-ip> --mongo-host <mongo-ip>
# Validate replication
bash shared/scripts/validate-replication.sh
```

## Common Operations

### Check Debezium connector status
```bash
curl http://<debezium-ip>:8083/connectors/postgres-source/status | jq .
curl http://<debezium-ip>:8083/connectors/mongodb-source/status | jq .
```

### Restart a failed connector
```bash
curl -X POST http://<debezium-ip>:8083/connectors/postgres-source/restart
```

### Check MirrorMaker 2 lag
```bash
/opt/kafka/bin/kafka-consumer-groups.sh --bootstrap-server <kafka-brokers> --describe --group mm2-source->target
```

### Check MSK Connect status
```bash
aws kafkaconnect list-connectors --query 'connectors[].{name:connectorName,state:currentState}'
```

### DR Failover Procedure
1. Verify Aurora DSQL US-E is in sync (check DSQL console)
2. Verify MongoDB US-E has recent data
3. Switch Route 53 to SECONDARY (or wait for automatic failover)
4. Update EKS apps in US-E to point to local DSQL/MongoDB endpoints
5. Verify US-E CloudFront is serving traffic

## Troubleshooting

### CDC lag increasing
1. Check Debezium connector status (should be RUNNING)
2. Check Kafka broker disk usage
3. Verify PostgreSQL WAL retention
4. Check MirrorMaker 2 consumer lag

### MSK Connect connector failing
1. Check CloudWatch logs: /aws/msk-connect/<connector-name>
2. Verify DSQL endpoint reachability from MSK Connect subnets
3. Check IAM role permissions
4. Restart connector: aws kafkaconnect update-connector --capacity ...

### Aurora DSQL connection issues
1. Verify VPC endpoint exists for DSQL
2. Check security group allows 443 from MSK Connect SG
3. Generate fresh IAM token: aws dsql generate-db-connect-auth-token
