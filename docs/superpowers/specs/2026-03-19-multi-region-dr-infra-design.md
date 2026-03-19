# Multi-Region DR Infrastructure Design Spec

**Date**: 2026-03-19
**Status**: Approved (Rev.3 - Final)
**IaC Tools**: Terraform + AWS CDK (TypeScript) dual implementation
**Regions**: US-WEST-2 (primary), US-EAST-1 (DR), US-EAST-2 (DSQL Witness)
**Reference Repos**: [aws_lab_infra](https://github.com/whchoi98/aws_lab_infra), [ec2_vscode](https://github.com/whchoi98/ec2_vscode)

---

## 1. Overview

### 1.1 Purpose

OnPrem 시뮬레이션 환경의 Database(PostgreSQL, MongoDB)를 AWS Aurora DSQL 및 MongoDB로 실시간 복제하는 인프라 구성.
복제 방식은 Debezium CDC → Kafka(EC2) → MirrorMaker 2 → MSK → MSK Connect + Confluent Connectors를 활용.
US-EAST-1은 DR(재해복구)용 리전으로 Aurora DSQL Multi-Region 연동.

### 1.2 Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| IaC Tool | Terraform + CDK (TypeScript) | 참조 레포 패턴 활용, 모듈 재사용성 |
| VPC Connectivity | Transit Gateway | 확장성, 크로스 리전 연동 최적 |
| CDC Pipeline | Debezium → Kafka(EC2) → MirrorMaker 2 → MSK → MSK Connect | MSK Replicator는 Self-managed Kafka 미지원, MM2로 대체 |
| MongoDB Replication | Debezium MongoDB Source → Kafka → MM2 → MSK → MongoDB Sink | PostgreSQL과 동일한 CDC 파이프라인 활용 |
| Aurora DSQL Access | PrivateLink VPC Endpoint | DSQL은 서버리스, VPC 외부 서비스. PrivateLink로 프라이빗 접근 |
| DSQL Witness Region | US-EAST-2 (Ohio) | Multi-Region DSQL 쿼럼에 필요, US-EAST-1과 근접 |
| EKS Deployment | eksctl (참조 레포 패턴) | Terraform/CDK는 VPC/서브넷만, EKS는 eksctl 관리 |

---

## 2. Network Architecture

### 2.1 VPC CIDR Allocation

#### OnPrem VPC (10.0.0.0/16) - US-WEST-2

| Subnet Type | AZ-a | AZ-b | CIDR Size | IPs |
|-------------|------|------|-----------|-----|
| Public | 10.0.0.0/24 | 10.0.1.0/24 | /24 | 256 |
| Private | 10.0.16.0/20 | 10.0.32.0/20 | /20 | 4,096 |
| Data | 10.0.48.0/23 | 10.0.50.0/23 | /23 | 512 |
| TGW Attachment | 10.0.252.0/24 | 10.0.253.0/24 | /24 | 256 |

#### US-W-CENTER VPC (10.1.0.0/16) - US-WEST-2

| Subnet Type | AZ-a | AZ-b | CIDR Size | IPs |
|-------------|------|------|-----------|-----|
| Public | 10.1.0.0/24 | 10.1.1.0/24 | /24 | 256 |
| Private | 10.1.16.0/20 | 10.1.32.0/20 | /20 | 4,096 |
| Data | 10.1.48.0/23 | 10.1.50.0/23 | /23 | 512 |
| TGW Attachment | 10.1.252.0/24 | 10.1.253.0/24 | /24 | 256 |

#### US-E-CENTER VPC (10.2.0.0/16) - US-EAST-1

| Subnet Type | AZ-a | AZ-b | CIDR Size | IPs |
|-------------|------|------|-----------|-----|
| Public | 10.2.0.0/24 | 10.2.1.0/24 | /24 | 256 |
| Private | 10.2.16.0/20 | 10.2.32.0/20 | /20 | 4,096 |
| Data | 10.2.48.0/23 | 10.2.50.0/23 | /23 | 512 |
| TGW Attachment | 10.2.252.0/24 | 10.2.253.0/24 | /24 | 256 |

### 2.2 Transit Gateway

| Component | Region | Config |
|-----------|--------|--------|
| TGW-West | us-west-2 | ASN 65000, OnPrem + US-W-CENTER VPC attached |
| TGW-East | us-east-1 | ASN 65001, US-E-CENTER VPC attached |
| Inter-Region Peering | us-west-2 ↔ us-east-1 | TGW Peering Attachment |

**Route Tables:**
- TGW-West: 10.0.0.0/16 → OnPrem, 10.1.0.0/16 → US-W-CENTER, 10.2.0.0/16 → Peering
- TGW-East: 10.2.0.0/16 → US-E-CENTER, 10.0.0.0/16 + 10.1.0.0/16 → Peering

### 2.3 NAT Gateway

- 각 VPC의 Public 서브넷에 AZ당 1개 (총 6개)
- Private/Data 서브넷 라우팅: 0.0.0.0/0 → NAT Gateway

### 2.4 VPC Endpoints (PrivateLink)

**각 VPC 공통:**
- `com.amazonaws.<region>.ssm` (SSM)
- `com.amazonaws.<region>.ssmmessages` (SSM Messages)
- `com.amazonaws.<region>.ec2messages` (EC2 Messages)

**US-W-CENTER & US-E-CENTER 추가:**
- `com.amazonaws.<region>.dsql` (Aurora DSQL PrivateLink)
  - MSK Connect 및 EKS에서 Aurora DSQL에 프라이빗 접근

### 2.5 Route 53 (DR Failover)

- Failover Routing Policy: Primary (US-WEST-2 CloudFront) / Secondary (US-EAST-1 CloudFront)
- Health Check: ALB 대상 TCP/HTTPS 헬스체크
- 리전 장애 시 자동 DNS 전환

---

## 3. Compute Layer

### 3.1 EKS Cluster (3 VPCs)

| Config | Value |
|--------|-------|
| Version | 1.33 |
| Subnets | Private subnets (2 AZ) |
| Node Type | t4g.2xlarge (Graviton ARM64) |
| Node Count | 8 |
| Deployment | eksctl |
| Addons | vpc-cni, coredns, kube-proxy, ebs-csi-driver, efs-csi-driver, aws-load-balancer-controller (v3.1.0), karpenter (v1.9.0), eks-pod-identity-agent, amazon-cloudwatch-observability |

### 3.2 CloudFront + ALB (3 VPCs)

> CloudFront는 글로벌 서비스. 3개 CloudFront Distribution이 각 리전의 ALB를 Origin으로 연결.

```
CloudFront Distribution (Global, HTTPS, TLS 1.2+)
  ↓ Custom Header: X-Custom-Secret: {StackName}-secret-{AccountId}
ALB (Public subnets, regional, CloudFront Prefix List SG)
  ↓ Listener Rule: validate X-Custom-Secret header (miss → 403)
EKS Ingress (Private subnets)
```

- ALB SG: CloudFront managed prefix list only (`com.amazonaws.global.cloudfront.origin-facing`)
- Custom Header 검증으로 직접 ALB 접근 차단

### 3.3 VSCode Server on EC2 (OnPrem VPC)

| Config | Value |
|--------|-------|
| Instance | m7g.xlarge |
| AMI | Amazon Linux 2023 ARM64 |
| Subnet | Private subnet (OnPrem VPC) |
| Storage | 100GB gp3 encrypted EBS |
| Access | CloudFront → ALB → code-server (port 8888) |
| Terminal | SSM Session Manager (SSH-free) |
| Tools | code-server v4.110.0, Claude Code, Docker, eksctl, kubectl, helm, python3, node20 |

---

## 4. Data Layer

### 4.1 OnPrem VPC - Source Databases

| Service | Instance | Subnet | Purpose |
|---------|----------|--------|---------|
| PostgreSQL on EC2 | r7g.large | Data-a | Source DB, CDC target |
| MongoDB on EC2 | r7g.large | Data-b | Source DB, CDC target |
| Kafka on EC2 | m7g.xlarge ×4 | Data-a(×2), Data-b(×2) | Self-managed 4-broker cluster (2+2 AZ 균등) |
| Debezium Connect EC2 | m7g.large | Data-a | Kafka Connect worker (Source Connectors) |
| MirrorMaker 2 EC2 | m7g.large | Data-a | OnPrem Kafka → US-W MSK 미러링 |

**Kafka Configuration:**
- 4 brokers across 2 AZ (2+2 균등 분배, AZ 장애 시에도 ISR 유지)
- Topics: `dbserver1.public.*` (Debezium PostgreSQL), `mongo.*.*` (Debezium MongoDB)
- Replication factor: 3, min.insync.replicas: 2

**Debezium on EC2:**
- Kafka Connect worker (standalone/distributed mode)
- PostgreSQL Source Connector: WAL logical replication 기반 CDC
- MongoDB Source Connector: Change Streams 기반 CDC

**MirrorMaker 2 on EC2:**
- Source cluster: OnPrem Kafka (localhost:9092, PLAINTEXT)
- Target cluster: US-W-CENTER MSK (TGW 경유, port 9098, SASL/IAM 인증)
  - MM2 EC2 IAM Instance Profile에 MSK 접근 권한 필요
  - `sasl.mechanism=AWS_MSK_IAM`, `sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule`
- Topic 미러링: `dbserver1.public.*`, `mongo.*.*`
- Consumer group offset sync 활성화
- Heartbeat/checkpoint 토픽 자동 생성

> **알려진 제한사항 (SPOF):** Debezium Connect EC2와 MirrorMaker 2 EC2는 각각 단일 인스턴스로 구성됩니다.
> 인스턴스 장애 시 CDC 파이프라인이 중단됩니다. 프로덕션 환경에서는 Distributed Mode(2+ worker)로
> 확장하거나 Auto Scaling Group(min=1)으로 자동 복구를 구성하는 것을 권장합니다.
> 테스트/랩 환경에서는 단일 인스턴스가 적합합니다.

### 4.2 US-W-CENTER VPC - Target Databases

| Service | Config | Subnet | Purpose |
|---------|--------|--------|---------|
| MongoDB on EC2 | r7g.large | Data-a | Replicated from OnPrem |
| Aurora DSQL | Multi-Region Primary | PrivateLink (VPC 외부) | PostgreSQL-compatible, CDC sink 대상 |
| Amazon MSK | 4× kafka.m7g.xlarge (2+2 AZ) | Data-a/b | Managed Kafka, MM2로부터 데이터 수신 |

**DSQL PrivateLink Endpoint:**
- VPC Interface Endpoint: `com.amazonaws.us-west-2.dsql`
- Private DNS 활성화
- Security Group: MSK Connect + EKS pods에서 443 접근 허용

**MSK Connect Connectors (US-W-CENTER):**
- Confluent JDBC Sink Connector: MSK → Aurora DSQL
  - DSQL IAM Token Auth를 위한 커스텀 JDBC URL 설정
  - `connection.url`: DSQL PrivateLink endpoint 사용
  - Insert/Upsert 모드, serialization error 자동 재시도 설정 (`errors.retry.timeout=300000`)
  - **IAM 토큰 리프레시**: DSQL IAM 토큰은 ~15분 만료. 커스텀 `ConnectionProvider` 구현 필요
    - AWS DSQL JDBC Driver의 `generateDbConnectAuthToken()` 활용
    - 커넥터 `connection.provider` 설정으로 토큰 자동 갱신
    - 대안: Lambda 기반 토큰 갱신 + Secrets Manager 연동
- MongoDB Sink Connector: MSK → MongoDB EC2
  - Confluent MongoDB Sink Connector
  - Upsert 모드 (document._id 기반)

**MSK Replicator (US-W → US-E):**
- Source: US-W-CENTER MSK cluster
- Target: US-E-CENTER MSK cluster
- MSK Replicator (관리형) - 둘 다 MSK이므로 지원됨

### 4.3 US-E-CENTER VPC - DR Databases

| Service | Config | Subnet | Purpose |
|---------|--------|--------|---------|
| MongoDB on EC2 | r7g.large | Data-a | Replicated via MSK |
| Aurora DSQL | Multi-Region Linked | PrivateLink (VPC 외부) | Auto-replicated from US-W |
| Amazon MSK | 4× kafka.m7g.xlarge (2+2 AZ) | Data-a/b | DR Kafka cluster |

**DSQL PrivateLink Endpoint:**
- VPC Interface Endpoint: `com.amazonaws.us-east-1.dsql`
- Private DNS 활성화

**MSK Connect Connectors (US-E-CENTER):**
- MongoDB Sink Connector: US-E MSK → US-E MongoDB EC2
  - US-W와 동일한 Confluent MongoDB Sink 설정

**Cross-Region Replication:**
- Aurora DSQL: Built-in multi-region replication (US-W ↔ US-E), Witness: US-EAST-2
- MongoDB: MSK Replicator (US-W MSK → US-E MSK) + MongoDB Sink Connector (US-E)
- MSK: MSK Replicator between US-W and US-E MSK clusters

---

## 5. Data Replication Architecture

### 5.1 PostgreSQL → Aurora DSQL Pipeline

```
OnPrem PostgreSQL (EC2)
  │ WAL (logical replication slot)
  ▼
Debezium PostgreSQL Source Connector (EC2, Kafka Connect)
  │ CDC events → JSON/Avro
  ▼
OnPrem Kafka (EC2, 4 brokers)
  │ Topics: dbserver1.public.<table>
  │
  │ MirrorMaker 2 (EC2, cross-VPC via TGW)
  ▼
US-W-CENTER Amazon MSK (managed)
  │ Topics: source.dbserver1.public.<table> (MM2 prefix)
  │
  │ MSK Connect (Confluent JDBC Sink)
  │ → PrivateLink VPC Endpoint
  ▼
Aurora DSQL (US-W-CENTER, Primary)
  │
  │ DSQL Multi-Region Replication (built-in, Witness: US-EAST-2)
  ▼
Aurora DSQL (US-E-CENTER, Linked)
```

### 5.2 MongoDB → MongoDB Pipeline

```
OnPrem MongoDB (EC2)
  │ Change Streams
  ▼
Debezium MongoDB Source Connector (EC2, Kafka Connect)
  │ CDC events → JSON
  ▼
OnPrem Kafka (EC2, 4 brokers)
  │ Topics: mongo.<db>.<collection>
  │
  │ MirrorMaker 2 (EC2, cross-VPC via TGW)
  ▼
US-W-CENTER Amazon MSK (managed)
  │ Topics: source.mongo.<db>.<collection>
  │
  │ MSK Connect (MongoDB Sink)
  ▼
US-W-CENTER MongoDB (EC2)

Cross-Region (DR):
US-W MSK → MSK Replicator (managed) → US-E MSK → MSK Connect (MongoDB Sink) → US-E MongoDB (EC2)
```

---

## 6. Security Architecture

### 6.1 Security Groups

#### OnPrem VPC

| SG Name | Inbound | Source | Purpose |
|---------|---------|--------|---------|
| sg-postgresql | TCP 5432 | Debezium SG, VSCode SG | PostgreSQL access |
| sg-mongodb | TCP 27017 | Debezium SG, VSCode SG | MongoDB access |
| sg-kafka | TCP 9092,9093 | Debezium SG, MM2 SG, self | Kafka broker |
| sg-debezium | TCP 8083 | VSCode SG (REST API) | Kafka Connect worker |
| sg-mm2 | - (outbound only) | - | MirrorMaker 2 → US-W MSK |
| sg-vscode | TCP 8888 | ALB SG | code-server |
| sg-alb-onprem | TCP 80,443 | CloudFront Prefix List | ALB |
| sg-eks-node | per-addon | EKS control plane, self | EKS worker nodes |

#### US-W-CENTER VPC

| SG Name | Inbound | Source | Purpose |
|---------|---------|--------|---------|
| sg-mongodb-usw | TCP 27017 | MSK Connect SG, EKS SG | MongoDB target |
| sg-msk-usw | TCP 9094(TLS),9098(IAM) | MM2(OnPrem via TGW), MSK Connect SG | MSK brokers |
| sg-msk-connect-usw | - (outbound only) | - | MSK Connect → MSK, DSQL, MongoDB |
| sg-dsql-endpoint | TCP 443 | MSK Connect SG, EKS SG | DSQL PrivateLink |
| sg-alb-usw | TCP 80,443 | CloudFront Prefix List | ALB |
| sg-eks-node-usw | per-addon | EKS control plane, self | EKS worker nodes |

#### US-E-CENTER VPC

| SG Name | Inbound | Source | Purpose |
|---------|---------|--------|---------|
| sg-mongodb-use | TCP 27017 | MSK Connect SG, EKS SG | MongoDB target |
| sg-msk-use | TCP 9094(TLS),9098(IAM) | MSK Replicator, MSK Connect SG | MSK brokers |
| sg-msk-connect-use | - (outbound only) | - | MSK Connect → MSK, MongoDB |
| sg-dsql-endpoint-use | TCP 443 | EKS SG | DSQL PrivateLink |
| sg-alb-use | TCP 80,443 | CloudFront Prefix List | ALB |
| sg-eks-node-use | per-addon | EKS control plane, self | EKS worker nodes |

### 6.2 Encryption

| Layer | Method |
|-------|--------|
| EBS Volumes | KMS encryption at rest (aws/ebs CMK) |
| Aurora DSQL | KMS at rest + TLS in transit (PrivateLink) |
| MSK | TLS in transit (9094) + KMS at rest |
| Kafka on EC2 | TLS inter-broker (9093) + SASL/PLAIN client |
| ALB ↔ CloudFront | HTTPS/TLS 1.2+ |
| SSM Session Manager | TLS encrypted channel |

### 6.3 Access Control

- EKS: EKS Pod Identity (eks-pod-identity-agent)
- EC2: IAM Instance Profiles + SSM Session Manager (SSH-free)
- MSK Connect: IAM execution role (MSK + DSQL + S3 plugin access)
- Aurora DSQL: IAM token-based authentication (aws_sigv4)
- MSK: IAM authentication (SASL/IAM, port 9098)

---

## 7. Monitoring & Observability

### 7.1 CloudWatch Metrics & Alarms

| Service | Key Metrics | Alarm Threshold |
|---------|------------|-----------------|
| MSK | `BytesInPerSec`, `BytesOutPerSec`, `UnderReplicatedPartitions` | UnderReplicated > 0 |
| MSK Connect | `ConnectorStatus`, `WorkerCount`, `SinkRecordLagMax` | Status != RUNNING, Lag > 10000 |
| MSK Replicator | `ReplicationLatency`, `MessageLag` | Latency > 30s |
| Aurora DSQL | `DatabaseConnections`, `ReadLatency`, `WriteLatency` | WriteLatency > 100ms |
| EKS | Container Insights (CPU, Memory, Pod status) | Node CPU > 80% |
| Kafka EC2 | `UnderReplicatedPartitions`, `ISRShrinkRate` (custom) | ISR shrink > 0 |

### 7.2 Logging

| Service | Log Destination | Retention |
|---------|----------------|-----------|
| EKS | CloudWatch Container Insights | 30 days |
| MSK | CloudWatch Logs (broker logs) | 14 days |
| MSK Connect | CloudWatch Logs (connector logs) | 14 days |
| Debezium | CloudWatch Agent (custom log) | 14 days |
| ALB | S3 (access logs) | 90 days |
| CloudFront | S3 (access logs) | 90 days |

### 7.3 SNS Alerting

- SNS Topic per region: `dr-lab-alerts-usw2`, `dr-lab-alerts-use1`
- Email subscription for critical alarms
- Lambda integration for Slack/Teams notifications (optional)

---

## 8. Backup & Recovery

| Resource | Backup Method | Retention | RPO |
|----------|--------------|-----------|-----|
| PostgreSQL EC2 | EBS automated snapshots (daily) + pg_dump (weekly) | 7 days / 30 days | 24h (snapshot), near-zero (CDC) |
| MongoDB EC2 | EBS automated snapshots (daily) + mongodump (weekly) | 7 days / 30 days | 24h (snapshot), near-zero (CDC) |
| Aurora DSQL | Managed automatic backups | Service-managed | Near-zero (multi-region) |
| Kafka EC2 | EBS snapshots (daily), topic retention 7 days | 7 days | Topic retention period |
| MSK | Managed (no user backup needed) | Service-managed | N/A |
| EKS Config | eksctl config YAML in git | Git history | Git restore |
| Terraform State | S3 + DynamoDB locking (required) | Versioned S3 | S3 versioning |

---

## 9. Test Data Generation

| Config | Value |
|--------|-------|
| Target DBs | OnPrem PostgreSQL + MongoDB |
| Data Size | 1GB ~ 10GB (configurable via CLI args) |
| Tool | Python script (Faker + psycopg2 + pymongo) |
| Data Types | Users, Orders, Products, Reviews (e-commerce mock data) |
| Execution | VSCode Server EC2 |
| Tables (PostgreSQL) | users, products, orders, order_items, reviews |
| Collections (MongoDB) | users, products, orders, reviews, sessions |

---

## 10. Project Structure

### 10.1 Terraform

```
terraform/
├── main.tf                          # Root module
├── providers.tf                     # AWS providers (us-west-2 default, us-east-1 alias)
├── variables.tf                     # Input variables
├── terraform.tfvars                 # Variable values
├── outputs.tf                       # Outputs
├── backend.tf                       # S3 + DynamoDB backend (required)
└── modules/
    ├── vpc/                         # Reusable VPC module (3 VPC common)
    │   ├── main.tf                  # VPC, subnets, route tables, NAT GW, IGW
    │   ├── variables.tf
    │   └── outputs.tf
    ├── vpc-endpoints/               # VPC Endpoints (SSM, DSQL PrivateLink)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── tgw/                         # Transit Gateway module
    │   ├── main.tf                  # TGW, attachments, route tables
    │   ├── variables.tf
    │   └── outputs.tf
    ├── tgw-peering/                 # Inter-Region TGW Peering
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── eks/                         # EKS (eksctl wrapper scripts)
    │   ├── main.tf                  # IAM roles, security groups
    │   ├── eksctl-config.yaml.tpl   # eksctl cluster config template
    │   ├── variables.tf
    │   └── outputs.tf
    ├── cloudfront-alb/              # CloudFront + ALB security
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── ec2-database/                # DB on EC2 (PostgreSQL, MongoDB, Kafka)
    │   ├── main.tf
    │   ├── user-data/
    │   │   ├── postgresql.sh
    │   │   ├── mongodb.sh
    │   │   ├── kafka.sh
    │   │   └── mirrormaker2.sh
    │   ├── variables.tf
    │   └── outputs.tf
    ├── debezium/                    # Debezium Kafka Connect worker on EC2
    │   ├── main.tf
    │   ├── user-data.sh
    │   ├── connector-configs/
    │   │   ├── postgres-source.json
    │   │   └── mongodb-source.json
    │   ├── variables.tf
    │   └── outputs.tf
    ├── msk/                         # Amazon MSK cluster
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── msk-connect/                 # MSK Connect connectors
    │   ├── main.tf
    │   ├── connector-configs/
    │   │   ├── confluent-jdbc-sink.json
    │   │   └── mongodb-sink.json
    │   ├── variables.tf
    │   └── outputs.tf
    ├── msk-replicator/              # MSK Replicator (US-W → US-E)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── aurora-dsql/                 # Aurora DSQL Multi-Region
    │   ├── main.tf                  # DSQL cluster (Primary + Linked + Witness)
    │   ├── variables.tf
    │   └── outputs.tf
    ├── monitoring/                  # CloudWatch alarms, dashboards, SNS
    │   ├── main.tf                  # Alarms, dashboards, log groups, SNS topics
    │   ├── variables.tf
    │   └── outputs.tf
    ├── vscode-server/               # VSCode Server on EC2
    │   ├── main.tf
    │   ├── user-data.sh
    │   ├── variables.tf
    │   └── outputs.tf
    └── test-data/                   # Test data generation
        ├── main.tf                  # null_resource for script execution
        ├── scripts/
        │   └── generate-test-data.py
        └── variables.tf
```

### 10.2 CDK (TypeScript)

```
cdk/
├── bin/app.ts                       # CDK entry point
├── lib/
│   ├── config.ts                    # Centralized config (CIDRs, tags, names)
│   ├── onprem-vpc-stack.ts          # OnPrem VPC stack
│   ├── usw-center-vpc-stack.ts      # US-W-CENTER VPC stack
│   ├── use-center-vpc-stack.ts      # US-E-CENTER VPC stack
│   ├── vpc-endpoints-stack.ts       # VPC Endpoints (SSM, DSQL PrivateLink)
│   ├── tgw-stack.ts                 # Transit Gateway (us-west-2)
│   ├── tgw-east-stack.ts            # Transit Gateway (us-east-1)
│   ├── tgw-peering-stack.ts         # Inter-Region TGW Peering
│   ├── eks-stack.ts                 # EKS placeholder (eksctl-managed)
│   ├── cloudfront-alb-stack.ts      # CloudFront + ALB per VPC
│   ├── data-onprem-stack.ts         # OnPrem data layer (PG, Mongo, Kafka, Debezium, MM2)
│   ├── data-usw-stack.ts            # US-W data layer (Mongo EC2, MSK, MSK Connect)
│   ├── data-use-stack.ts            # US-E data layer (Mongo EC2, MSK, MSK Connect)
│   ├── aurora-dsql-stack.ts         # Aurora DSQL Multi-Region (Primary + Linked + Witness)
│   ├── msk-replicator-stack.ts      # MSK Replicator (US-W → US-E)
│   ├── monitoring-stack.ts          # CloudWatch alarms, dashboards, SNS
│   ├── route53-failover-stack.ts    # Route 53 DR failover
│   └── vscode-server-stack.ts       # VSCode Server on EC2
├── package.json
├── tsconfig.json
└── cdk.json
```

### 10.3 Shared Scripts

```
shared/
├── scripts/
│   ├── check-prerequisites.sh       # Tool validation (aws, eksctl, kubectl, helm, jq)
│   ├── eks-create-cluster.sh        # eksctl-based EKS creation
│   ├── eks-setup-env.sh             # EKS environment variables
│   ├── deploy-app.sh                # Application deployment
│   ├── generate-test-data.py        # Test data generation (1GB~10GB)
│   ├── setup-debezium.sh            # Debezium connector setup/registration
│   ├── setup-mirrormaker2.sh        # MirrorMaker 2 configuration
│   └── cloudfront-protection.sh     # CloudFront → ALB protection setup
├── configs/
│   ├── debezium-postgres-source.json
│   ├── debezium-mongodb-source.json
│   ├── confluent-jdbc-sink.json
│   ├── mongodb-sink.json
│   ├── mirrormaker2.properties
│   └── eksctl-cluster-config.yaml
└── docs/
    └── runbook.md                   # Operational runbook
```

---

## 11. Deployment Sequence

### Phase 1: Networking
1. OnPrem VPC (10.0.0.0/16) in us-west-2
2. US-W-CENTER VPC (10.1.0.0/16) in us-west-2
3. US-E-CENTER VPC (10.2.0.0/16) in us-east-1
4. VPC Endpoints (SSM all 3, DSQL PrivateLink for US-W/US-E)
5. TGW (us-west-2) + OnPrem & US-W-CENTER attachments
6. TGW (us-east-1) + US-E-CENTER attachment
7. TGW Inter-Region Peering + Route propagation

### Phase 2: Security & Ingress
8. CloudFront Distribution × 3 (global) + ALB × 3 (regional)
9. CloudFront protection (prefix list SG + custom header)
10. Route 53 Failover Routing (Primary: US-W CloudFront, Secondary: US-E CloudFront)

### Phase 3: Compute
11. EKS clusters (3 VPCs) via eksctl
12. EKS addons (LBC, Karpenter, Pod Identity, Container Insights)
13. VSCode Server EC2 (OnPrem VPC)

### Phase 4: Data Layer - OnPrem
14. PostgreSQL on EC2 (OnPrem)
15. MongoDB on EC2 (OnPrem)
16. Kafka on EC2 (OnPrem, 4 brokers, 2+2 AZ)

### Phase 5: Data Layer - AWS
17. Amazon MSK (US-W-CENTER)
18. Amazon MSK (US-E-CENTER)
19. Aurora DSQL Multi-Region (Primary: US-W-2, Linked: US-E-1, Witness: US-E-2)
20. MongoDB on EC2 (US-W-CENTER)
21. MongoDB on EC2 (US-E-CENTER)

### Phase 6: Replication Setup
22. Debezium Kafka Connect worker (OnPrem EC2)
23. Debezium PostgreSQL Source Connector 등록
24. Debezium MongoDB Source Connector 등록
25. (토픽 자동 생성 대기)
26. MirrorMaker 2 시작 (OnPrem Kafka → US-W MSK)
27. MSK Replicator 생성 (US-W MSK → US-E MSK)
28. MSK Connect - Confluent JDBC Sink (US-W MSK → Aurora DSQL)
29. MSK Connect - MongoDB Sink (US-W MSK → US-W MongoDB)
30. MSK Connect - MongoDB Sink (US-E MSK → US-E MongoDB)

### Phase 7: Testing & Validation
31. Generate test data (1GB~10GB) from VSCode Server
32. Verify Debezium CDC → OnPrem Kafka
33. Verify MirrorMaker 2 → US-W MSK
34. Verify MSK Connect Sink → Aurora DSQL (US-W)
35. Verify Aurora DSQL Multi-Region → US-E
36. Verify MongoDB replication → US-W and US-E
37. Verify Route 53 failover (optional manual test)

---

## 12. Tagging Strategy

```
Environment: dr-lab
Project: us-h-dr
ManagedBy: terraform | cdk
Region: us-west-2 | us-east-1
VPC: onprem | us-w-center | us-e-center
Component: network | compute | data | replication | monitoring
```
