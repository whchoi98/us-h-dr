# Project Context

## Overview
**us-h-dr** - Multi-Region DR Infrastructure for database replication from OnPrem to AWS.
3 VPCs (OnPrem/US-W-CENTER in us-west-2, US-E-CENTER in us-east-1) with EKS 1.33, real-time CDC replication via Debezium + MirrorMaker 2 + MSK + Aurora DSQL.

## Tech Stack
- **IaC (Dual)**: Terraform >= 1.0 (AWS Provider >= 5.0) + AWS CDK 2.180.0 (TypeScript)
- **Container**: EKS 1.33 (eksctl), Karpenter v1.9.0, AWS LBC v3.1.0
- **Database**: PostgreSQL 16, MongoDB 7.0, Aurora DSQL (serverless, multi-region)
- **Streaming**: Apache Kafka 3.7.0 (EC2), Amazon MSK (managed), MirrorMaker 2
- **CDC**: Debezium 2.7.0, Confluent JDBC Sink, MongoDB Sink Connector
- **Networking**: Transit Gateway, Inter-Region Peering, CloudFront + ALB
- **Languages**: HCL (Terraform), TypeScript (CDK), Python 3 (test data), Bash (scripts)

## Project Structure
```
terraform/          - Terraform modules and root configuration
  modules/          - 16 reusable modules (vpc, tgw, msk, eks, etc.)
  main.tf           - Root module with all 30 module instantiations
  providers.tf      - Multi-region providers (us-west-2, us-east-1, us-east-2)
cdk/                - AWS CDK TypeScript implementation
  lib/              - 21 stack files mirroring Terraform modules
  bin/app.ts        - CDK entry point with stack dependencies
shared/             - Cross-IaC shared resources
  scripts/          - Deployment, setup, and validation scripts
  configs/          - Debezium, MM2, MSK Connect connector configs
  docs/             - Operational runbook
docs/               - Architecture docs, ADRs, specs, plans
  superpowers/      - Design specs and implementation plans
  decisions/        - Architecture Decision Records
  runbooks/         - Operational runbooks
.claude/            - Claude Code settings, hooks, skills
tools/              - Utility scripts and prompts
```

## Conventions
- **Terraform naming**: `module_name` (snake_case), resource tags include `Environment`, `Project`, `ManagedBy`, `VPC`, `Component`
- **CDK naming**: PascalCase for stack classes, camelCase for props
- **Commit messages**: `feat:`, `fix:`, `docs:` prefixes, imperative mood
- **All child modules**: Must have `required_providers` block with `aws` source
- **Subnet tiers**: public (/24), private (/20), data (/23), tgw (/24) across 2 AZs
- **Security**: CloudFront prefix list + custom header for ALB, PrivateLink for DSQL, IAM auth for MSK (port 9098), no PLAINTEXT (9092)
- **Provider aliases**: `aws` (us-west-2 default), `aws.us_east_1`, `aws.us_east_2`

## Key Commands

### Terraform
```bash
cd terraform
terraform init -backend=false          # Local state (dev)
terraform fmt -recursive               # Format all files
terraform validate                     # Validate configuration
terraform plan -var="vscode_password=<pw>"  # Plan all resources
terraform apply -target=module.<name>  # Deploy specific module
```

### CDK
```bash
cd cdk
npm install                            # Install dependencies
npx tsc --noEmit                       # Type check
npx cdk list                           # List all 21 stacks
npx cdk synth <StackName>             # Synthesize specific stack
npx cdk deploy <StackName>            # Deploy specific stack
```

### EKS (via eksctl)
```bash
bash shared/scripts/check-prerequisites.sh    # Verify tools
bash shared/scripts/eks-create-cluster.sh <config.yaml>
bash shared/scripts/eks-setup-env.sh <region> <cluster>
bash shared/scripts/deploy-app.sh <cluster> <region>
```

### Replication Setup
```bash
bash shared/scripts/setup-debezium.sh <debezium-ip> <pg-ip> <mongo-ip> <kafka-brokers>
bash shared/scripts/setup-mirrormaker2.sh <source-brokers> <target-msk-brokers>
```

### Testing
```bash
pip3 install -r shared/scripts/requirements.txt
python3 shared/scripts/generate-test-data.py --size 1 --pg-host <ip> --mongo-host <ip>
bash shared/scripts/validate-replication.sh
```

---

## Auto-Sync Rules

Rules below are applied automatically after Plan mode exit and on major code changes.

### Post-Plan Mode Actions
After exiting Plan mode (`/plan`), before starting implementation:

1. **Architecture decision made** -> Update `docs/architecture.md`
2. **Technical choice/trade-off made** -> Create `docs/decisions/ADR-NNN-title.md`
3. **New module added** -> Create `CLAUDE.md` in that module directory
4. **Operational procedure defined** -> Create runbook in `docs/runbooks/`
5. **Changes needed in this file** -> Update relevant sections above

### Code Change Sync Rules
- New Terraform module created -> Must have `required_providers`, `variables.tf`, `outputs.tf`
- New CDK stack created -> Must be imported in `bin/app.ts` with dependency chain
- Terraform module changed -> Run `terraform fmt && terraform validate`
- CDK stack changed -> Run `npx tsc --noEmit`
- Infrastructure changed -> Update `docs/architecture.md` Infrastructure section
- Connector config changed -> Update corresponding `shared/configs/` JSON

### ADR Numbering
Find the highest number in `docs/decisions/ADR-*.md` and increment by 1.
Format: `ADR-NNN-concise-title.md`
