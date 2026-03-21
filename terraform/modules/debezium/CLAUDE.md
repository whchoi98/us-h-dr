# Debezium Module

## Role
EC2 instance running Debezium Kafka Connect for CDC from PostgreSQL (WAL) and MongoDB (Change Streams).

## Key Inputs
`instance_type`, `subnet_id`, `kafka_sg_id`, `kafka_brokers`

## Key Outputs
`instance_id`, `private_ip`, `sg_id`

## Notes
- Connectors registered via REST API (`shared/scripts/setup-debezium.sh`)
- SG allows 8083 from VSCode for management
