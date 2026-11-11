# Demo Module

## Role
Interactive multi-region DR migration demo with test data generation, CDC pipeline verification, and DR failover simulation.

## Key Files
- `run-demo.sh` - Main orchestrator (deploy/seed/pipeline/verify/dr-test/cleanup)
- `demo.env.example` - Environment template (copy to demo.env)
- `k8s/demo-app.yaml` - K8s manifests (Flask API + ConfigMap + Service + Ingress)
- `scripts/deploy-lbc-and-app.sh` - LBC + Retail Store app (hardening overlay) + CloudFront for 3 clusters
- `cfn/cloudfront-ui.yaml` - CloudFront distribution for the UI ALB (no SG rules — owned by LBC)
- `README.md` - Demo data flow diagram and usage guide

## Usage
```bash
cp demo.env.example demo.env   # Fill in Terraform outputs
./run-demo.sh all               # Full interactive demo
./run-demo.sh cleanup           # Clean everything
```

## Rules
- Each run generates a unique `batch_id` for isolated demo data
- Demo API uses public Python image (no ECR/container build needed)
- Cleanup removes both K8s resources and database records
- LBC-managed ALBs: restrict access only via Ingress annotations (`security-group-prefix-lists`, `actions.*`) — CLI/CFN edits to their SGs are reverted on LBC resync (ADR-002)
