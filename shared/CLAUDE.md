# Shared Module

## Role
Cross-IaC shared scripts, connector configurations, and operational documentation. Used by both Terraform and CDK deployments.

## Key Files
- `scripts/check-prerequisites.sh` - Verify required tools (aws, eksctl, kubectl, helm, jq)
- `scripts/generate-test-data.py` - Generate 1-10GB e-commerce test data (PG + MongoDB)
- `scripts/setup-debezium.sh` - Register Debezium CDC connectors via REST API
- `scripts/setup-mirrormaker2.sh` - Configure and start MirrorMaker 2
- `scripts/validate-replication.sh` - End-to-end CDC pipeline validation
- `configs/` - JSON/properties connector configurations (Debezium, MM2, JDBC Sink, MongoDB Sink)
- `docs/runbook.md` - Full operational runbook with deployment phases and troubleshooting

## Rules
- All `.sh` scripts must be executable (`chmod +x`)
- Config files use `${VARIABLE}` placeholders for environment-specific values
- Test data script requires: `pip3 install -r scripts/requirements.txt`
- Scripts are designed to run from VSCode Server EC2 in OnPrem VPC
