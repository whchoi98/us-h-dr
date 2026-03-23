---
name: refactor
description: Refactor existing code to improve quality without changing behavior. Use when asked to refactor, restructure, or clean up code.
---

# Refactor

## Principles
- Improve structure without changing behavior
- Single Responsibility, DRY
- Small incremental steps with verification

## Process
1. **Analysis**: Identify target, map dependencies (Terraform: main.tf refs, CDK: app.ts imports), verify `terraform validate` / `npx tsc --noEmit` passes
2. **Plan**: Present what changes, what stays, risk level
3. **Execute**: Small verifiable steps, run validation after each change
4. **Verify**: `terraform plan` shows no unintended changes, `cdk list` shows all stacks, no unexpected destroy/recreate
