# MSK Module

## Role
Amazon MSK cluster with IAM+TLS authentication, KMS encryption, and enhanced monitoring.

## Key Inputs
`cluster_name`, `kafka_version`, `broker_instance_type`, `number_of_broker_nodes`, `subnet_ids`

## Key Outputs
`cluster_arn`, `bootstrap_brokers_iam`, `bootstrap_brokers_tls`, `security_group_id`

## Security
- IAM auth (port 9098), TLS (port 9094) only — no PLAINTEXT (9092)
- In-transit + at-rest encryption enabled
