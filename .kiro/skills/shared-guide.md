---
name: shared-guide
description: Shared scripts, configs, and demo conventions for the us-h-dr project. Use when working with shared/ directory files.
---

# Shared Guide

## Structure
- `scripts/` — Deployment, setup, validation scripts (check-prerequisites, generate-test-data, setup-debezium, etc.)
- `configs/` — Connector JSON/properties (Debezium, MM2, JDBC Sink, MongoDB Sink)
- `demo/` — Interactive E2E demo (demo-e2e.sh, deploy-lbc-and-app.sh, k8s manifests)
- `docs/runbook.md` — Operational runbook

## Rules
- All `.sh` scripts must be executable (`chmod +x`)
- Config files use `${VARIABLE}` placeholders for environment-specific values
- Test data script requires: `pip3 install -r scripts/requirements.txt`
- Scripts designed to run from VSCode Server EC2 in OnPrem VPC
