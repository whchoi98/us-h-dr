# Architecture

## System Overview

Multi-region DR infrastructure spanning US-WEST-2 (primary) and US-EAST-1 (DR) with real-time database replication from an OnPrem simulation environment to AWS managed services.

```
┌─────────────── US-WEST-2 ────────────────┐   TGW Peering   ┌──── US-EAST-1 ────┐
│ OnPrem VPC (10.0.0.0/16)                 │                  │ US-E-CENTER VPC    │
│  - PostgreSQL, MongoDB, Kafka(×4)        │                  │  (10.2.0.0/16)     │
│  - Debezium CDC, MirrorMaker 2           │                  │  - MongoDB EC2     │
│  - EKS 1.33, VSCode Server              │                  │  - Aurora DSQL     │
│                                          │                  │  - MSK (4 brokers) │
│ US-W-CENTER VPC (10.1.0.0/16)           │                  │  - EKS 1.33        │
│  - MSK (4 brokers), MSK Connect         │                  │                    │
│  - Aurora DSQL (Primary)                │                  │                    │
│  - MongoDB EC2, EKS 1.33               │                  │                    │
└──────────────────────────────────────────┘                  └────────────────────┘
```

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| **OnPrem VPC** | us-west-2 | Simulates on-premises with self-managed DBs and Kafka |
| **US-W-CENTER VPC** | us-west-2 | AWS target for replicated data (MSK, DSQL, MongoDB) |
| **US-E-CENTER VPC** | us-east-1 | DR region with Aurora DSQL linked + MSK mirror |
| **Transit Gateway** | Both regions | Hub-spoke VPC connectivity + inter-region peering |
| **CloudFront + ALB** | All 3 VPCs | Secure ingress with custom header protection |
| **EKS 1.33** | All 3 VPCs | Container orchestration (eksctl-managed) |
| **Aurora DSQL** | us-west-2 + us-east-1 | Serverless PostgreSQL-compatible, multi-region (witness: us-east-2) |
| **Amazon MSK** | us-west-2 + us-east-1 | Managed Kafka for CDC event processing |
| **MSK Connect** | us-west-2 + us-east-1 | Sink connectors (JDBC → DSQL, MongoDB Sink) |
| **MSK Replicator** | Cross-region | Replicates MSK topics from US-W to US-E |

## Data Flow

### PostgreSQL CDC Pipeline
```
OnPrem PostgreSQL → Debezium (WAL CDC) → Kafka (EC2) → MirrorMaker 2 → MSK (US-W)
  → MSK Connect (JDBC Sink) → Aurora DSQL (US-W) → DSQL Multi-Region → Aurora DSQL (US-E)
```

### MongoDB CDC Pipeline
```
OnPrem MongoDB → Debezium (Change Streams) → Kafka (EC2) → MirrorMaker 2 → MSK (US-W)
  → MSK Connect (MongoDB Sink) → MongoDB EC2 (US-W)
  → MSK Replicator → MSK (US-E) → MSK Connect (MongoDB Sink) → MongoDB EC2 (US-E)
```

## Infrastructure

### IaC (Dual Implementation)
- **Terraform**: 16 modules, 282 planned resources, multi-region providers
- **CDK (TypeScript)**: 21 stacks mirroring Terraform architecture

### Networking
- 3 VPCs with 4 subnet tiers (public, private, data, TGW attachment)
- 6 NAT Gateways, 2 Transit Gateways with inter-region peering
- VPC Endpoints: SSM (all), DSQL PrivateLink (US-W/US-E)
- Route 53 failover routing for DR

### Security
- CloudFront prefix list restricting ALB access
- Custom X-Custom-Secret header validation
- MSK: IAM auth (port 9098) + TLS encryption (port 9094)
- Aurora DSQL: IAM token-based auth via PrivateLink
- SSM Session Manager for EC2 access (no SSH)
