# Test Data Module

## Role
Triggers test data generation script on the VSCode Server EC2 via SSM Run Command.

## Key Inputs
`data_size_gb`, `vscode_instance_id`, `pg_host`, `mongo_host`

## Notes
- Invokes `shared/scripts/generate-test-data.py` via SSM
- Generates e-commerce data: customers, orders, products, reviews, sessions
