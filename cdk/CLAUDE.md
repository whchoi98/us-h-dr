# CDK Module

## Role
AWS CDK TypeScript implementation mirroring the Terraform architecture. 21 stacks with full dependency chain.

## Key Files
- `bin/app.ts` - Entry point, all stack instantiations with dependencies
- `lib/config.ts` - Centralized configuration (CIDRs, instance types, etc.)
- `lib/constructs/vpc-construct.ts` - Reusable VPC construct
- `lib/*-stack.ts` - 16 individual stack files

## Rules
- All stacks must be imported and instantiated in `bin/app.ts`
- Use `addDependency()` to wire stack dependencies
- Cross-region references require `crossRegionReferences: true`
- Run `npx tsc --noEmit` after any change
- VPC stacks: 3 separate files per spec (onprem, usw-center, use-center)
- L1 constructs (CfnResource) used for DSQL, MSK Replicator, MSK Connect
