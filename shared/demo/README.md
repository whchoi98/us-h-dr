# DR Lab Migration Demo

Interactive demonstration of multi-region database replication from OnPrem to AWS.

## Data Flow

```
┌─── OnPrem VPC (us-west-2) ──────────────────────────────────────────────┐
│                                                                          │
│  CloudFront → ALB → EKS Pod (Demo API)                                 │
│                        ├─→ PostgreSQL (customers, orders)               │
│                        └─→ MongoDB (products, inventory)                │
│                                                                          │
│  Debezium CDC ──→ Kafka (4 brokers) ──→ MirrorMaker 2 ────────────────┼──┐
└──────────────────────────────────────────────────────────────────────────┘  │
                                                                              │
┌─── US-W-CENTER VPC (us-west-2) ────────────────────────────────────────┐  │
│                                                                          │  │
│  MSK (4 brokers) ←──────────────────────────────────────────────────────┼──┘
│    ├─→ MSK Connect (JDBC Sink)  → Aurora DSQL (Primary) ───────────────┼──┐
│    ├─→ MSK Connect (Mongo Sink) → MongoDB EC2                          │  │
│    └─→ MSK Replicator ─────────────────────────────────────────────────┼──┼──┐
│                                                                          │  │  │
└──────────────────────────────────────────────────────────────────────────┘  │  │
                                                                              │  │
┌─── US-E-CENTER VPC (us-east-1) — DR ───────────────────────────────────┐  │  │
│                                                                          │  │  │
│  Aurora DSQL (Linked) ←── auto multi-region replication ────────────────┼──┘  │
│  MSK (4 brokers) ←── MSK Replicator ───────────────────────────────────┼─────┘
│    └─→ MSK Connect (Mongo Sink) → MongoDB EC2                          │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Quick Start

```bash
# 1. Configure environment
cp demo.env.example demo.env
# Fill in values from Terraform/CDK outputs (IPs, endpoints, etc.)

# 2. Run full interactive demo
./run-demo.sh all

# 3. Run individual steps
./run-demo.sh deploy     # Deploy Demo API to OnPrem EKS
./run-demo.sh seed       # Generate test data
./run-demo.sh pipeline   # Check CDC pipeline status
./run-demo.sh verify     # Verify replication across all regions
./run-demo.sh dr-test    # Simulate DR failover
./run-demo.sh cleanup    # Remove all demo resources and data
```

## Prerequisites

- `kubectl` configured with EKS cluster access
- `aws` CLI with appropriate credentials
- `psql` (PostgreSQL client) for DSQL verification
- `mongosh` (MongoDB Shell) for MongoDB verification
- Debezium and MirrorMaker2 already running
- MSK Connect connectors already configured

## Demo Data

Each run creates a unique `batch_id` (e.g., `demo_20260321_143052`), enabling:
- Multiple demo runs without data conflicts
- Selective cleanup by batch
- Easy verification filtering

| Database | Table | Records | Description |
|----------|-------|---------|-------------|
| PostgreSQL | customers | N | Name, email, city per customer |
| PostgreSQL | orders | ~2N | 1-3 orders per customer |
| MongoDB | products | N | Product catalog with tags |
| MongoDB | inventory | N | Warehouse stock levels |

## Cleanup

```bash
# Remove specific demo batch
./run-demo.sh cleanup

# Or manually:
kubectl delete namespace dr-demo
```
