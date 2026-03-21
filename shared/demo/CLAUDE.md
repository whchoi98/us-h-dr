# Demo Module

## Role
Interactive multi-region DR migration demo with test data generation, CDC pipeline verification, and DR failover simulation.

## Key Files
- `run-demo.sh` - Main orchestrator (deploy/seed/pipeline/verify/dr-test/cleanup)
- `demo.env.example` - Environment template (copy to demo.env)
- `k8s/demo-app.yaml` - K8s manifests (Flask API + ConfigMap + Service + Ingress)
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
