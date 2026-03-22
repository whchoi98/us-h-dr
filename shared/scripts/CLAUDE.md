# Scripts Module

## Role
Operational shell scripts and Python utilities for infrastructure setup, data generation, and replication validation.

## Key Files
- `check-prerequisites.sh` - Verify required tools (aws, eksctl, kubectl, helm, jq)
- `generate-test-data.py` - Generate 1-10GB e-commerce test data (PG + MongoDB)
- `setup-debezium.sh` - Register Debezium CDC connectors via REST API
- `setup-mirrormaker2.sh` - Configure and start MirrorMaker 2
- `validate-replication.sh` - End-to-end CDC pipeline validation
- `deploy-app.sh` - Deploy sample app to EKS with ALB Ingress
- `cloudfront-protection.sh` - Add CloudFront prefix list to ALB SG
- `eks-create-cluster.sh` - Create EKS cluster via eksctl config
- `eks-setup-env.sh` - Source to set EKS environment variables
- `requirements.txt` - Python dependencies (pinned versions)

## Rules
- All `.sh` scripts must have `set -e` and be executable
- Config placeholders use `${VARIABLE}` syntax
- Scripts designed to run from VSCode Server EC2 or EKS Pod
