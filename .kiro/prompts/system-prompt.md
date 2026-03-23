# us-h-dr: Multi-Region DR Infrastructure

## Overview
Real-time database replication from simulated OnPrem to AWS with cross-region Disaster Recovery.
3 VPCs (OnPrem/US-W-CENTER in us-west-2, US-E-CENTER in us-east-1) with EKS 1.33, CDC replication via Debezium → Kafka → MirrorMaker 2 → Amazon MSK → MSK Connect → Aurora DSQL + MongoDB.

## Tech Stack
- **IaC (Dual)**: Terraform >= 1.0 (AWS Provider >= 5.0) + AWS CDK 2.180.0 (TypeScript)
- **Container**: EKS 1.33 (eksctl), AWS LBC v3.1.0
- **Database**: PostgreSQL 16, MongoDB 7.0, Aurora DSQL (serverless, multi-region)
- **Streaming**: Apache Kafka 3.7.0 (KRaft, EC2), Amazon MSK (managed), MirrorMaker 2
- **CDC**: Debezium 2.7.0, Confluent JDBC Sink, MongoDB Sink Connector
- **Networking**: Transit Gateway, Inter-Region Peering, CloudFront + ALB
- **Languages**: HCL (Terraform), TypeScript (CDK), Python 3 (test data), Bash (scripts)

## Project Structure
```
terraform/          - Root config + 16 modules (vpc, tgw, msk, eks, aurora-dsql, etc.)
  main.tf           - 30 module instantiations + security groups + cross-VPC routes
  providers.tf      - 3 AWS providers (default us-west-2, us_east_1, us_east_2)
cdk/                - CDK TypeScript (21 stacks mirroring Terraform)
  lib/              - Stack files + config.ts + constructs/
  bin/app.ts        - Entry point with stack dependencies
shared/             - Cross-IaC scripts, configs, demo
  scripts/          - Deployment, setup, validation scripts
  configs/          - Debezium, MM2, MSK Connect connector JSON/properties
  demo/             - Interactive E2E demo (demo-e2e.sh)
docs/               - Architecture, ADRs, runbooks
```

## Conventions

### Terraform
- `snake_case` naming for modules and resources
- All child modules MUST have `required_providers` block with `aws` source
- Security groups defined in `main.tf` (cross-module references)
- Provider aliases: `aws` (us-west-2 default), `aws.us_east_1`, `aws.us_east_2`
- Tags: `Environment`, `Project`, `ManagedBy`, `VPC`, `Component`
- Subnet tiers: public (/24), private (/20), data (/23), tgw (/24) across 2 AZs
- Run `terraform fmt -recursive && terraform validate` after any change

### CDK
- PascalCase for stack classes, camelCase for props
- All stacks imported and instantiated in `bin/app.ts` with `addDependency()`
- Cross-region: `crossRegionReferences: true`
- L1 constructs (CfnResource) for DSQL, MSK Replicator, MSK Connect
- Run `npx tsc --noEmit` after any change

### Security
- CloudFront prefix list + custom header for ALB (direct ALB access blocked)
- MSK: IAM auth (port 9098) + TLS, no PLAINTEXT (9092)
- Aurora DSQL: IAM token-based auth via PrivateLink
- EKS: KMS Secrets encryption, 5-type control plane logging
- EC2: SSM Session Manager (no SSH keys)
- IAM: Least privilege, resource ARN scoped

### Commits
- Prefixes: `feat:`, `fix:`, `docs:`, imperative mood

## Key Commands

### Terraform
```bash
cd terraform
terraform init -backend=false
terraform fmt -recursive
terraform validate
terraform plan -var="vscode_password=<pw>"
terraform apply -target=module.<name>
```

### CDK
```bash
cd cdk
npm install
npx tsc --noEmit
npx cdk list
npx cdk synth <StackName>
npx cdk deploy <StackName>
```

### EKS + Demo
```bash
bash shared/scripts/check-prerequisites.sh
cd shared/demo
./demo-e2e.sh all          # Full interactive demo
./demo-e2e.sh check        # Infrastructure health
./demo-e2e.sh seed         # Seed data
./demo-e2e.sh verify       # Verify replication
./demo-e2e.sh dr-failover  # DR failover simulation
```

### Replication Setup
```bash
bash shared/scripts/setup-debezium.sh <debezium-ip> <pg-ip> <mongo-ip> <kafka-brokers>
bash shared/scripts/setup-mirrormaker2.sh <source-brokers> <target-msk-brokers>
```

## Auto-Sync Rules

After code changes:
- New Terraform module → Must have `required_providers`, `variables.tf`, `outputs.tf`
- New CDK stack → Must be imported in `bin/app.ts` with dependency chain
- Terraform change → `terraform fmt && terraform validate`
- CDK change → `npx tsc --noEmit`
- Infrastructure change → Update `docs/architecture.md`
- Connector config change → Update `shared/configs/` JSON
- Architecture decision → Create `docs/decisions/ADR-NNN-title.md`

### ADR Numbering
Find highest `docs/decisions/ADR-*.md` and increment by 1. Format: `ADR-NNN-concise-title.md`
