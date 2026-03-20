# us-h-dr: Multi-Region DR Infrastructure

Multi-region AWS infrastructure for real-time database replication from OnPrem simulation to AWS, with DR failover capability.

## Architecture

- **3 VPCs**: OnPrem (10.0.0.0/16), US-W-CENTER (10.1.0.0/16), US-E-CENTER (10.2.0.0/16)
- **2 Regions**: US-WEST-2 (primary) + US-EAST-1 (DR)
- **CDC Pipeline**: Debezium -> Kafka -> MirrorMaker 2 -> MSK -> MSK Connect -> Aurora DSQL / MongoDB
- **Dual IaC**: Terraform (16 modules, 282 resources) + CDK TypeScript (21 stacks)

## Quick Start

### Prerequisites
```bash
bash shared/scripts/check-prerequisites.sh
```

### Terraform
```bash
cd terraform
terraform init
terraform plan -var="vscode_password=<password>"
terraform apply -target=module.onprem_vpc    # Deploy phase by phase
```

### CDK
```bash
cd cdk
npm install
npx cdk list
npx cdk deploy OnpremVpcStack
```

## Project Structure

```
terraform/          16 reusable modules (vpc, tgw, msk, eks, dsql, etc.)
cdk/                21 CDK stacks mirroring Terraform
shared/
  scripts/          Deployment, replication setup, test data, validation
  configs/          Debezium, MirrorMaker 2, MSK Connect configs
  docs/             Operational runbook
docs/
  architecture.md   System architecture overview
  decisions/        Architecture Decision Records
  superpowers/      Design specs and implementation plans
```

## Key Components

| Component | OnPrem (us-west-2) | US-W-CENTER (us-west-2) | US-E-CENTER (us-east-1) |
|-----------|-------------------|------------------------|------------------------|
| EKS 1.33 | Yes | Yes | Yes |
| PostgreSQL | EC2 (source) | Aurora DSQL (target) | Aurora DSQL (DR) |
| MongoDB | EC2 (source) | EC2 (target) | EC2 (DR) |
| Kafka | EC2 (4 brokers) | MSK (4 brokers) | MSK (4 brokers) |
| CDC | Debezium + MM2 | MSK Connect (Sink) | MSK Connect (Sink) |

## Documentation

- [Architecture](docs/architecture.md)
- [Design Spec](docs/superpowers/specs/2026-03-19-multi-region-dr-infra-design.md)
- [Implementation Plan](docs/superpowers/plans/2026-03-19-multi-region-dr-infra.md)
- [Operational Runbook](shared/docs/runbook.md)
