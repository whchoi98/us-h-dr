# us-h-dr: Multi-Region DR Infrastructure

Real-time database replication from simulated OnPrem to AWS with cross-region Disaster Recovery. CDC pipeline streams PostgreSQL and MongoDB changes through Debezium → Kafka → MirrorMaker 2 → Amazon MSK → MSK Connect to Aurora DSQL and MongoDB targets across two AWS regions.

## Architecture

```
┌───── OnPrem VPC (us-west-2, 10.0.0.0/16) ──────────────────────────────────┐
│                                                                              │
│  CloudFront → ALB → EKS 1.33 (Demo API)                                    │
│                        ├→ PostgreSQL 16                                      │
│                        └→ MongoDB 7.0 (ReplicaSet)                          │
│                                                                              │
│  Debezium 2.7 (CDC) → Kafka KRaft 3.7 (×4) → MirrorMaker 2 ──────────────┼──┐
└──────────────────────────────────────────────────────────────────────────────┘  │
                                                                    TGW          │
┌───── US-W-CENTER VPC (us-west-2, 10.1.0.0/16) ─────────────────────────────┐  │
│                                                                              │  │
│  Amazon MSK (IAM auth, 4 brokers) ←─────────────────────────────────────────┼──┘
│    ├→ MSK Connect (JDBC Sink) → Aurora DSQL Primary ────────────────────────┼──┐
│    ├→ MSK Connect (MongoDB Sink) → MongoDB EC2                              │  │
│    └→ MSK Replicator (cross-region) ────────────────────────────────────────┼──┼──┐
│  CloudFront → ALB → EKS 1.33                                               │  │  │
└──────────────────────────────────────────────────────────────────────────────┘  │  │
                                                                                  │  │
┌───── US-E-CENTER VPC (us-east-1, 10.2.0.0/16) ── DR Region ────────────────┐  │  │
│                                                                              │  │  │
│  Aurora DSQL Linked ←── auto multi-region replication ──────────────────────┼──┘  │
│  Amazon MSK (IAM auth) ←── MSK Replicator ──────────────────────────────────┼─────┘
│    └→ MSK Connect (MongoDB Sink) → MongoDB EC2                              │
│  CloudFront → ALB → EKS 1.33                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Key Components

| Component | OnPrem (us-west-2) | US-W-CENTER (us-west-2) | US-E-CENTER (us-east-1) |
|-----------|:------------------:|:-----------------------:|:-----------------------:|
| **EKS 1.33** | 4 nodes | 4 nodes | 4 nodes |
| **CloudFront + ALB** | ✅ CF Prefix List | ✅ CF Prefix List | ✅ CF Prefix List |
| **PostgreSQL** | EC2 (source) | Aurora DSQL (target) | Aurora DSQL (DR) |
| **MongoDB** | EC2 ReplicaSet (source) | EC2 (target) | EC2 (DR) |
| **Kafka** | KRaft 3.7 × 4 brokers | MSK (IAM, 4 brokers) | MSK (IAM, 4 brokers) |
| **CDC** | Debezium 2.7 + MM2 | MSK Connect (Sink) | MSK Connect (Sink) |
| **Replication** | — | MSK Replicator (source) | MSK Replicator (target) |
| **Networking** | TGW attachment | TGW attachment | TGW peering (cross-region) |

## Data Flow

```
[1] App writes to OnPrem PostgreSQL + MongoDB
[2] Debezium captures CDC events (WAL / Change Streams)         < 1s
[3] Events published to OnPrem Kafka topics                      < 1s
[4] MirrorMaker 2 replicates to MSK US-W (IAM auth)            < 3s
[5] MSK Connect sinks to US-W targets (DSQL + MongoDB)          < 5s
[6] MSK Replicator mirrors to MSK US-E (cross-region)          < 10s
[7] MSK Connect sinks to US-E targets (MongoDB)                 < 5s
[8] Aurora DSQL auto-replicates to US-E Linked cluster          < 1s

    Total: OnPrem INSERT → US-E DR arrival ≈ 15-20 seconds
```

## Tech Stack

| Category | Technology | Version |
|----------|-----------|---------|
| **IaC** | Terraform + AWS CDK (TypeScript) | >= 1.0 / 2.180.0 |
| **Container** | Amazon EKS (eksctl) | 1.33 |
| **Compute** | AWS Graviton (t4g/m7g/r7g) ARM64 | — |
| **Database** | PostgreSQL, MongoDB, Aurora DSQL | 16 / 7.0 / Serverless |
| **Streaming** | Apache Kafka (KRaft), Amazon MSK | 3.7.0 |
| **CDC** | Debezium, Confluent JDBC Sink, MongoDB Sink | 2.7.0 |
| **Networking** | Transit Gateway, Inter-Region Peering | — |
| **Ingress** | CloudFront + ALB (Prefix List protection) | — |
| **Load Balancer** | AWS Load Balancer Controller (Helm) | v3.1.0 |

## Project Structure

```
us-h-dr/
├── terraform/                  # Terraform root + 16 modules
│   ├── main.tf                 # 30 module instantiations + SGs + routes
│   ├── providers.tf            # Multi-region (us-west-2, us-east-1, us-east-2)
│   ├── variables.tf            # All project variables
│   ├── outputs.tf              # 18 outputs for demo.env generation
│   └── modules/
│       ├── vpc/                # VPC with 4 subnet tiers (public/private/data/tgw)
│       ├── tgw/                # Transit Gateway + VPC attachments
│       ├── tgw-peering/        # Inter-region TGW peering
│       ├── cloudfront-alb/     # CloudFront + ALB with custom header protection
│       ├── eks/                # EKS IAM roles, SGs, eksctl config template
│       ├── vscode-server/      # Browser IDE (code-server) on EC2
│       ├── vpc-endpoints/      # SSM + DSQL PrivateLink endpoints
│       ├── ec2-database/       # Generic EC2 factory (PG, MongoDB, Kafka)
│       ├── debezium/           # Debezium Kafka Connect EC2
│       ├── msk/                # Amazon MSK (IAM + TLS, KMS encrypted)
│       ├── msk-connect/        # MSK Connect connector (JDBC/MongoDB Sink)
│       ├── msk-replicator/     # Cross-region MSK Replicator
│       ├── aurora-dsql/        # Multi-region DSQL (primary + linked + witness)
│       ├── monitoring/         # CloudWatch alarms + SNS
│       ├── route53-failover/   # Active-passive DNS failover
│       └── test-data/          # Test data generation via SSM
│
├── cdk/                        # AWS CDK TypeScript (21 stacks)
│   ├── bin/app.ts              # Entry point with stack dependencies
│   ├── lib/config.ts           # Centralized configuration
│   ├── lib/constructs/         # Reusable constructs (VPC)
│   └── lib/*-stack.ts          # 16 stack files
│
├── shared/
│   ├── scripts/                # Bash/Python operational scripts
│   │   ├── setup-debezium.sh   # Register Debezium CDC connectors
│   │   ├── setup-mirrormaker2.sh
│   │   ├── generate-test-data.py  # 1-10GB e-commerce data generator
│   │   ├── validate-replication.sh
│   │   └── deploy-app.sh      # EKS sample app deployment
│   ├── configs/                # Connector JSON/properties configs
│   │   ├── debezium-postgres-source.json
│   │   ├── debezium-mongodb-source.json
│   │   ├── mirrormaker2.properties
│   │   ├── confluent-jdbc-sink.json
│   │   └── mongodb-sink.json
│   └── demo/                   # Interactive demo environment
│       ├── DEMO-SCENARIO.md    # Detailed 7-step demo walkthrough
│       ├── demo-e2e.sh         # Visual E2E demo script
│       ├── run-demo.sh         # Original demo orchestrator
│       ├── demo.env.example    # Environment template
│       ├── k8s/demo-app.yaml   # Demo API (Flask) K8s manifests
│       └── scripts/
│           ├── deploy-lbc-and-app.sh  # LBC + app + CF (3 clusters)
│           └── generate-demo-env.sh   # Auto-generate demo.env from TF
│
├── docs/
│   ├── architecture.md         # System architecture overview
│   ├── decisions/
│   │   └── ADR-001-dsql-pending-setup.md
│   └── runbooks/
│
└── .claude/                    # Claude Code project structure
    ├── settings.json           # Permissions + hooks
    ├── hooks/check-doc-sync.sh # Auto-detect missing docs
    └── skills/                 # code-review, refactor, release, sync-docs
```

## Quick Start

### Prerequisites
```bash
bash shared/scripts/check-prerequisites.sh
# Required: aws, eksctl, kubectl, helm, jq, python3, docker
```

### Deploy Infrastructure (Terraform)
```bash
cd terraform
terraform init -backend=false
terraform plan -var="vscode_password=<password>"
terraform apply -target=module.onprem_vpc     # Deploy phase by phase
```

### Deploy Infrastructure (CDK)
```bash
cd cdk
npm install
npx tsc --noEmit                              # Type check
npx cdk list                                  # List 21 stacks
npx cdk deploy OnpremVpcStack                 # Deploy by stack
```

### Deploy EKS + Apps (3 clusters)
```bash
cd shared/demo
# Create EKS clusters (parallel)
eksctl create cluster -f onprem-eks-cluster.yaml
eksctl create cluster -f usw-eks-cluster.yaml
eksctl create cluster -f use-eks-cluster.yaml

# Deploy LBC + sample app + CloudFront protection (all 3)
bash scripts/deploy-lbc-and-app.sh
```

### Generate demo.env from Terraform Outputs
```bash
terraform output -raw demo_env > shared/demo/demo.env
# or
bash shared/demo/scripts/generate-demo-env.sh
```

## Demo

Interactive demo that demonstrates the full CDC replication pipeline with visual output.

### Run Full Demo
```bash
cd shared/demo
./demo-e2e.sh all          # Full interactive (Enter to advance steps)
```

### Individual Steps
```bash
./demo-e2e.sh check        # 1. Infrastructure health check
./demo-e2e.sh seed         # 2. Seed data (auto-deploys API + connectors)
./demo-e2e.sh pipeline     # 3. Trace CDC pipeline
./demo-e2e.sh verify       # 4+5. Verify US-W and US-E targets
./demo-e2e.sh dr-failover  # 6. DR failover simulation
./demo-e2e.sh cleanup      # 7. Remove demo data and resources
```

### Demo Output Example
```
━━━ EKS Clusters (3 clusters, 12 nodes) ━━━
  PASS  onprem-eks: 4 nodes Ready
  PASS  usw-eks: 4 nodes Ready
  PASS  use-eks: 4 nodes Ready

━━━ Inserting Records ━━━
  ┌────────────────────────────────────────────┐
  │  Batch ID: demo_20260322_222739            │
  │  PostgreSQL: 20 customers, 43 orders       │
  │  MongoDB: 20 products, 20 inventory        │
  └────────────────────────────────────────────┘

━━━ US-E MongoDB (DR) — via MSK Replicator ━━━
  PASS  source.ecommerce.products: 100 records
  PASS  source.ecommerce.inventory: 60 records

━━━ DR Failover 절차 ━━━
  READY  Aurora DSQL (US-E) — active-active auto replication
  READY  MongoDB (US-E) — MSK Replicator pipeline
  READY  EKS (US-E) — app + ALB + CloudFront ready
```

## Security

- **CloudFront → ALB**: Managed Prefix List + X-Custom-Secret header (direct ALB access blocked)
- **MSK**: IAM authentication (port 9098) + TLS encryption, no PLAINTEXT
- **Aurora DSQL**: IAM token-based auth via PrivateLink
- **EKS**: KMS Secrets encryption, 5-type control plane logging
- **S3**: KMS encryption + public access block + versioning
- **EC2**: SSM Session Manager (no SSH keys)
- **IAM**: Least privilege policies scoped to specific resource ARNs

## Key Decisions

| Decision | Details |
|----------|---------|
| **KRaft over ZooKeeper** | Kafka 3.7 KRaft mode eliminates ZooKeeper dependency |
| **IdentityReplicationPolicy** | MM2 preserves original topic names on MSK (no prefix duplication) |
| **MSK Replicator** | AWS-managed cross-region replication (vs. running MM2 on target) |
| **DSQL over Aurora PostgreSQL** | Serverless, automatic multi-region with < 1s replication |
| **Dual IaC** | Terraform for primary deployment, CDK as TypeScript alternative |

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Demo Scenario (detailed walkthrough)](shared/demo/DEMO-SCENARIO.md)
- [ADR-001: Aurora DSQL Multi-Region Setup](docs/decisions/ADR-001-dsql-pending-setup.md)
- [Operational Runbook](shared/docs/runbook.md)

---

# us-h-dr: 멀티 리전 DR 인프라

시뮬레이션된 온프레미스 환경에서 AWS로의 실시간 데이터베이스 복제 및 크로스 리전 재해복구(DR) 인프라입니다. CDC 파이프라인이 PostgreSQL과 MongoDB의 변경 사항을 Debezium → Kafka → MirrorMaker 2 → Amazon MSK → MSK Connect를 통해 Aurora DSQL과 MongoDB 타겟으로 스트리밍합니다.

## 아키텍처

```
┌───── 온프레미스 VPC (us-west-2, 10.0.0.0/16) ──────────────────────────────┐
│                                                                              │
│  CloudFront → ALB → EKS 1.33 (데모 API)                                    │
│                        ├→ PostgreSQL 16                                      │
│                        └→ MongoDB 7.0 (레플리카셋)                          │
│                                                                              │
│  Debezium 2.7 (CDC) → Kafka KRaft 3.7 (×4) → MirrorMaker 2 ──────────────┼──┐
└──────────────────────────────────────────────────────────────────────────────┘  │
                                                                    TGW          │
┌───── US-W-CENTER VPC (us-west-2, 10.1.0.0/16) ─────────────────────────────┐  │
│                                                                              │  │
│  Amazon MSK (IAM 인증, 4 브로커) ←──────────────────────────────────────────┼──┘
│    ├→ MSK Connect (JDBC Sink) → Aurora DSQL Primary ────────────────────────┼──┐
│    ├→ MSK Connect (MongoDB Sink) → MongoDB EC2                              │  │
│    └→ MSK Replicator (크로스 리전) ─────────────────────────────────────────┼──┼──┐
│  CloudFront → ALB → EKS 1.33                                               │  │  │
└──────────────────────────────────────────────────────────────────────────────┘  │  │
                                                                                  │  │
┌───── US-E-CENTER VPC (us-east-1, 10.2.0.0/16) ── DR 리전 ──────────────────┐  │  │
│                                                                              │  │  │
│  Aurora DSQL Linked ←── 자동 멀티리전 복제 ─────────────────────────────────┼──┘  │
│  Amazon MSK (IAM 인증) ←── MSK Replicator ──────────────────────────────────┼─────┘
│    └→ MSK Connect (MongoDB Sink) → MongoDB EC2                              │
│  CloudFront → ALB → EKS 1.33                                               │
└──────────────────────────────────────────────────────────────────────────────┘
```

## 주요 구성 요소

| 구성 | 온프레미스 (us-west-2) | US-W-CENTER (us-west-2) | US-E-CENTER (us-east-1) |
|------|:---------------------:|:-----------------------:|:-----------------------:|
| **EKS 1.33** | 4 노드 | 4 노드 | 4 노드 |
| **CloudFront + ALB** | ✅ CF Prefix List | ✅ CF Prefix List | ✅ CF Prefix List |
| **PostgreSQL** | EC2 (소스) | Aurora DSQL (타겟) | Aurora DSQL (DR) |
| **MongoDB** | EC2 레플리카셋 (소스) | EC2 (타겟) | EC2 (DR) |
| **Kafka** | KRaft 3.7 × 4 | MSK (IAM, 4 브로커) | MSK (IAM, 4 브로커) |
| **CDC** | Debezium 2.7 + MM2 | MSK Connect (Sink) | MSK Connect (Sink) |
| **복제** | — | MSK Replicator (소스) | MSK Replicator (타겟) |

## 데이터 흐름

```
[1] 앱이 온프레미스 PostgreSQL + MongoDB에 데이터 쓰기
[2] Debezium이 CDC 이벤트 캡처 (WAL / Change Streams)          < 1초
[3] 온프레미스 Kafka 토픽에 이벤트 발행                          < 1초
[4] MirrorMaker 2가 MSK US-W로 복제 (IAM 인증)                < 3초
[5] MSK Connect가 US-W 타겟에 적재 (DSQL + MongoDB)            < 5초
[6] MSK Replicator가 MSK US-E로 크로스 리전 복제              < 10초
[7] MSK Connect가 US-E 타겟에 적재 (MongoDB)                   < 5초
[8] Aurora DSQL이 US-E Linked 클러스터로 자동 복제             < 1초

    전체 지연: 온프레미스 INSERT → US-E DR 도착 ≈ 15-20초
```

## 빠른 시작

### 사전 요구사항
```bash
bash shared/scripts/check-prerequisites.sh
# 필요 도구: aws, eksctl, kubectl, helm, jq, python3, docker
```

### 인프라 배포 (Terraform)
```bash
cd terraform
terraform init -backend=false
terraform plan -var="vscode_password=<비밀번호>"
terraform apply -target=module.onprem_vpc     # 단계별 배포
```

### EKS + 앱 배포 (3개 클러스터)
```bash
cd shared/demo
eksctl create cluster -f onprem-eks-cluster.yaml   # 3개 병렬 생성 가능
eksctl create cluster -f usw-eks-cluster.yaml
eksctl create cluster -f use-eks-cluster.yaml
bash scripts/deploy-lbc-and-app.sh                  # LBC + 앱 + CloudFront 일괄 배포
```

## 데모 실행

CDC 복제 파이프라인 전체를 시각적으로 시연하는 대화형 데모입니다.

```bash
cd shared/demo
./demo-e2e.sh all          # 전체 대화형 데모 (Enter로 단계 진행)
./demo-e2e.sh check        # 1. 인프라 상태 확인
./demo-e2e.sh seed         # 2. 데이터 생성 (API + 커넥터 자동 배포)
./demo-e2e.sh pipeline     # 3. CDC 파이프라인 추적
./demo-e2e.sh verify       # 4+5. US-W + US-E 타겟 검증
./demo-e2e.sh dr-failover  # 6. DR 페일오버 시뮬레이션
./demo-e2e.sh cleanup      # 7. 데모 리소스 정리
```

## 보안

- **CloudFront → ALB**: 관리형 Prefix List + 커스텀 헤더 (ALB 직접 접근 차단)
- **MSK**: IAM 인증 (포트 9098) + TLS 암호화, PLAINTEXT 미사용
- **Aurora DSQL**: IAM 토큰 기반 인증 via PrivateLink
- **EKS**: KMS Secrets 암호화, 5종 컨트롤 플레인 로깅
- **S3**: KMS 암호화 + 퍼블릭 접근 차단 + 버전관리
- **EC2**: SSM 세션 매니저 (SSH 키 미사용)
- **IAM**: 리소스 ARN 기반 최소 권한 정책

## 문서

- [아키텍처 개요](docs/architecture.md)
- [데모 시나리오 (상세 워크스루)](shared/demo/DEMO-SCENARIO.md)
- [ADR-001: Aurora DSQL 멀티리전 설정](docs/decisions/ADR-001-dsql-pending-setup.md)
- [운영 런북](shared/docs/runbook.md)
