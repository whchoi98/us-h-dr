# Multi-Region DR Migration Demo Scenario

## Overview

OnPrem 데이터센터에서 AWS로의 실시간 데이터베이스 마이그레이션 및 DR(Disaster Recovery) 구성을 시연합니다.
PostgreSQL과 MongoDB의 CDC(Change Data Capture) 파이프라인을 통해 3개 리전에 데이터가 자동 복제되는 과정을 단계별로 보여줍니다.

## Architecture

```
┌──────────────────────────── OnPrem VPC (us-west-2, 10.0.0.0/16) ────────────────────────────┐
│                                                                                               │
│   [CloudFront] ──→ [ALB] ──→ [EKS Pod: Demo API]                                            │
│                                    │                                                          │
│                          ┌─────────┴─────────┐                                               │
│                          ▼                   ▼                                                │
│                   [PostgreSQL]          [MongoDB]                                             │
│                   10.0.20.79            10.0.21.83                                            │
│                          │                   │                                                │
│                          ▼                   ▼                                                │
│                   [Debezium Kafka Connect]  ← CDC (WAL + Change Streams)                     │
│                   10.0.20.15                                                                  │
│                          │                                                                    │
│                          ▼                                                                    │
│                   [Apache Kafka KRaft × 4]  ← source.public.* / source.ecommerce.*          │
│                   10.0.20.208/222, 10.0.21.175/169                                           │
│                          │                                                                    │
│                   [MirrorMaker 2]  ← IdentityReplicationPolicy (IAM auth to MSK)            │
└──────────────────────────┼────────────────────────────────────────────────────────────────────┘
                           │ TGW
┌──────────────────────────┼──── US-W-CENTER VPC (us-west-2, 10.1.0.0/16) ─────────────────────┐
│                          ▼                                                                     │
│                   [Amazon MSK]  ← source.public.customers / source.ecommerce.products         │
│                          │                                                                     │
│              ┌───────────┼───────────┐                                                        │
│              ▼                       ▼                                                         │
│   [MSK Connect: JDBC Sink]   [MSK Connect: MongoDB Sink]                                     │
│              │                       │                                                         │
│              ▼                       ▼                                                         │
│   [Aurora DSQL Primary]       [MongoDB EC2]                                                   │
│   (active-active)              10.1.20.150                                                    │
│              │                                                                                 │
│              │ auto replication                                                                │
│              ▼                                                                                 │
│   ┌─────────────────────────────────────┐                                                     │
│   │    MSK Replicator (cross-region)    │                                                     │
│   └────────────────┬────────────────────┘                                                     │
└────────────────────┼──────────────────────────────────────────────────────────────────────────┘
                     │ Inter-Region
┌────────────────────┼──── US-E-CENTER VPC (us-east-1, 10.2.0.0/16) ── DR Region ──────────────┐
│                    ▼                                                                           │
│             [Amazon MSK]  ← {alias}.source.ecommerce.products (replicated)                    │
│                    │                                                                           │
│                    ▼                                                                           │
│        [MSK Connect: MongoDB Sink]                                                            │
│                    │                                                                           │
│                    ▼                                                                           │
│             [MongoDB EC2]          [Aurora DSQL Linked]                                        │
│             10.2.20.68             (auto-replicated from Primary)                              │
│                                                                                                │
│             [EKS + ALB + CloudFront]  ← DR 앱 즉시 전환 가능                                  │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

| 구성 요소 | 상태 | 확인 방법 |
|-----------|:----:|-----------|
| EKS 3개 클러스터 | ✅ | `kubectl --context onprem-eks get nodes` |
| CloudFront + ALB | ✅ | 브라우저에서 CF URL 접속 |
| PostgreSQL (OnPrem) | ✅ | SSM 또는 EKS Pod에서 `psql` |
| MongoDB (OnPrem/US-W/US-E) | ✅ | SSM 또는 EKS Pod에서 `mongosh` |
| Kafka KRaft 4대 | ✅ | SSM: `systemctl is-active kafka` |
| Debezium + MM2 | ✅ | SSM: `curl localhost:8083/connectors` |
| MSK (US-W/US-E) | ✅ | AWS Console 또는 `aws kafka list-clusters-v2` |
| MSK Connect (3 sinks) | ✅ | `aws kafkaconnect list-connectors` |
| MSK Replicator | ✅ | `aws kafka list-replicators` |
| Aurora DSQL (Primary + Linked) | ✅ | `aws dsql get-cluster` |

---

## Demo Steps

### Step 1. 인프라 상태 확인

**목적**: 3개 리전의 모든 구성 요소가 정상인지 확인

```bash
./demo-e2e.sh check
```

**확인 항목**:
- EKS 3개 클러스터 (각 4 nodes)
- Demo API Pod (2 replicas)
- Debezium 커넥터 2개 (demo-pg, demo-mongo: RUNNING)
- MSK Connect Sink 3개 (RUNNING)
- MSK Replicator (RUNNING)
- Aurora DSQL (ACTIVE, 양쪽 linked)

---

### Step 2. 데이터 생성 (OnPrem → PostgreSQL + MongoDB)

**목적**: CloudFront → ALB → EKS Pod → DB 경로로 데이터를 생성하여, 앱에서 DB로의 정상적인 쓰기 흐름을 시연

```bash
./demo-e2e.sh seed
```

**생성 데이터**:
| Database | Table/Collection | Records | Schema |
|----------|-----------------|---------|--------|
| PostgreSQL | `customers` | 20건 | id, name, email, city, batch_id |
| PostgreSQL | `orders` | ~40건 | id, customer_id, product, amount, status, batch_id |
| MongoDB | `products` | 20건 | product_id, name, category, price, batch_id |
| MongoDB | `inventory` | 20건 | product_id, warehouse, quantity, batch_id |

**핵심 포인트**: 각 실행마다 고유 `batch_id` (예: `demo_20260322_170924`)로 데이터가 격리되어, 반복 실행 시 이전 데이터와 충돌하지 않습니다.

---

### Step 3. CDC 파이프라인 추적

**목적**: 데이터가 Debezium → Kafka → MirrorMaker2 → MSK로 실시간 전파되는 과정을 확인

```bash
./demo-e2e.sh pipeline
```

**확인 항목**:
1. **Debezium 커넥터 상태**: demo-pg(RUNNING), demo-mongo(RUNNING)
2. **OnPrem Kafka 토픽**: `source.public.customers`, `source.public.orders`, `source.ecommerce.products`, `source.ecommerce.inventory`
3. **MSK US-W 토픽**: MM2가 IdentityReplicationPolicy로 동일 이름 복제
4. **MSK US-W 메시지 샘플**: 실제 CDC 이벤트 JSON 확인

**CDC 이벤트 예시**:
```json
{
  "before": null,
  "after": {
    "id": 85,
    "name": "DemoFinal_20260322_170924_0",
    "email": "demo0@final.test",
    "city": "Seoul",
    "batch_id": "demo_final_20260322_170924"
  },
  "source": {
    "connector": "postgresql",
    "table": "customers"
  },
  "op": "c"
}
```

---

### Step 4. US-W 타겟 검증

**목적**: MSK Connect Sink가 데이터를 US-W MongoDB + Aurora DSQL에 정상 적재했는지 확인

```bash
./demo-e2e.sh verify-usw
```

**검증 대상**:
| Target | Expected | 복제 경로 |
|--------|----------|-----------|
| US-W MongoDB | products 컬렉션에 데이터 존재 | MSK US-W → MongoDB Sink → MongoDB EC2 |
| Aurora DSQL Primary | dsql_test 테이블 존재 | MSK US-W → JDBC Sink → DSQL |

---

### Step 5. US-E DR 타겟 검증

**목적**: MSK Replicator를 통한 크로스 리전 복제와 DSQL 자동 복제를 확인하여, DR 리전의 데이터 가용성을 시연

```bash
./demo-e2e.sh verify-use
```

**검증 대상**:
| Target | Expected | 복제 경로 |
|--------|----------|-----------|
| US-E MongoDB | products 컬렉션에 데이터 존재 | MSK Replicator → MSK US-E → MongoDB Sink → MongoDB EC2 |
| Aurora DSQL Linked | dsql_test 테이블 동일 데이터 | DSQL Primary → 자동 multi-region 복제 |

---

### Step 6. DR Failover 시뮬레이션

**목적**: OnPrem 장애 시 US-E에서 즉시 서비스를 재개할 수 있음을 시연

```bash
./demo-e2e.sh dr-failover
```

**시나리오**:
1. OnPrem 장애 발생 (시뮬레이션)
2. US-E EKS 클러스터 확인 (이미 앱 배포됨)
3. US-E MongoDB 데이터 확인 (복제된 데이터 사용 가능)
4. US-E DSQL 데이터 확인 (자동 복제된 데이터 사용 가능)
5. Route 53 → US-E CloudFront로 DNS 전환 (수동)

**DR Readiness 체크리스트**:
- ✅ Aurora DSQL (US-E): active-active, 자동 복제
- ✅ MongoDB (US-E): MSK Replicator 경유 복제 완료
- ✅ EKS (US-E): 클러스터 + 앱 + ALB + CloudFront 준비 완료
- 📋 Route 53: DNS를 US-E CloudFront로 전환하면 서비스 재개

---

### Step 7. 정리 (Cleanup)

**목적**: 데모 데이터와 리소스를 정리하여 다음 데모를 준비

```bash
./demo-e2e.sh cleanup
```

**정리 대상**:
- OnPrem PostgreSQL: demo 테이블 데이터 삭제
- OnPrem MongoDB: demo 컬렉션 데이터 삭제
- Debezium: demo 커넥터 삭제 + PG replication slot 제거
- K8s: dr-demo 네임스페이스 삭제

---

## Data Flow Summary

```
시간순서 →

[1] 앱이 OnPrem DB에 데이터 쓰기 (INSERT)
     │
[2] Debezium이 WAL/Change Stream 감지 (< 1초)
     │
[3] Kafka 토픽에 CDC 이벤트 발행 (< 1초)
     │
[4] MirrorMaker2가 MSK US-W로 복제 (< 3초)
     │
[5] MSK Connect가 US-W 타겟 DB에 적재 (< 5초)
     │  ├── JDBC Sink → Aurora DSQL Primary
     │  └── MongoDB Sink → MongoDB US-W
     │
[6] MSK Replicator가 US-E MSK로 크로스 리전 복제 (< 10초)
     │
[7] MSK Connect가 US-E 타겟 DB에 적재 (< 5초)
     │  └── MongoDB Sink → MongoDB US-E
     │
[8] Aurora DSQL 자동 multi-region 복제 (< 1초)
     └── DSQL Primary → DSQL Linked (US-E)

총 지연: OnPrem INSERT → US-E 도착까지 약 15-20초
```

---

## Repeat Demo

```bash
# 정리 후 재실행
./demo-e2e.sh cleanup
./demo-e2e.sh all        # 전체 데모 (Step 1~7)

# 개별 단계만 실행
./demo-e2e.sh seed       # 데이터만 추가
./demo-e2e.sh verify     # 전체 검증만
```
