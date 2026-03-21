# EC2 Database Module

## Role
Generic EC2 instance factory for self-managed databases (PostgreSQL, MongoDB, Kafka brokers).

## Key Inputs
`instances` (map with instance_type, subnet_id, user_data_file, sg_ids, name), `vpc_name`

## Key Outputs
`instance_ids`, `private_ips`

## Notes
- User data scripts in `user-data/` subdirectory
- AL2023 ARM64, 200GB GP3 EBS, encrypted
- SSM-managed (no SSH keys)
