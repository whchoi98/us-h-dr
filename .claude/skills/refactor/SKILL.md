# Refactor Skill

Refactor existing code to improve quality without changing behavior.

## Principles
- Improve structure without changing behavior
- Single Responsibility Principle (SRP)
- Remove duplicate code (DRY)
- Small, incremental steps with verification

## Process

### 1. Analysis
- Identify the target code and its dependencies
- Map all references (Terraform: module calls in main.tf, CDK: imports in app.ts)
- Confirm `terraform validate` / `npx tsc --noEmit` passes before changes

### 2. Plan
Present the refactoring plan:
- What will change
- What will NOT change (behavior preservation)
- Risk assessment (low/medium/high)

### 3. Execute
- Make changes in small, verifiable steps
- Run `terraform fmt && terraform validate` after each Terraform change
- Run `npx tsc --noEmit` after each CDK change
- Keep commits atomic

### 4. Verify
- Confirm `terraform plan` shows no unintended changes
- Confirm `cdk list` shows all expected stacks
- Check that no resources are destroyed/recreated unexpectedly

## Usage
Run with `/refactor` command
