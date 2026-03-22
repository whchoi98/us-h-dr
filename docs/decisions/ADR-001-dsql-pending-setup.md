# ADR-001: Aurora DSQL Multi-Region Setup

## Status
Resolved

## Context
Aurora DSQL multi-region cluster pair (primary us-west-2 + linked us-east-1 + witness us-east-2) was created via Terraform but initially remained in PENDING_SETUP status. The two clusters referenced only themselves in `multiRegionProperties.clusters`, not each other.

## Root Cause
Terraform `aws_dsql_cluster` created two independent clusters with `multiRegionProperties.witnessRegion` but did not establish the peer link between them.

## Resolution
Used `aws dsql update-cluster` to add each cluster as a peer of the other:

```bash
aws dsql update-cluster --identifier <primary-id> --region us-west-2 \
  --multi-region-properties '{"witnessRegion":"us-east-2","clusters":["<primary-arn>","<linked-arn>"]}'

aws dsql update-cluster --identifier <linked-id> --region us-east-1 \
  --multi-region-properties '{"witnessRegion":"us-east-2","clusters":["<primary-arn>","<linked-arn>"]}'
```

Both clusters transitioned PENDING_SETUP → ACTIVE within 30 seconds. EKS node roles also needed `dsql:DbConnectAdmin` IAM permission.

## Verification
- US-W Primary: INSERT test row → success
- US-E Linked: SELECT same row → multi-region replication confirmed ✅

## Action Items
- Update Terraform DSQL module to properly link clusters during creation
- Add DSQL IAM permissions to EKS node roles in Terraform
