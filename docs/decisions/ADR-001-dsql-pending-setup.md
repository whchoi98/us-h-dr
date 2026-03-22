# ADR-001: Aurora DSQL Multi-Region Status

## Status
Accepted

## Context
Aurora DSQL multi-region cluster pair (primary us-west-2 + linked us-east-1 + witness us-east-2) was created via Terraform but remains in PENDING_SETUP status. The two clusters reference themselves in `multiRegionProperties.clusters` instead of each other, indicating the multi-region link was not established.

## Decision
Document DSQL as a known limitation for the current demo. The JDBC Sink connector is configured and RUNNING, but cannot write to DSQL until the cluster is ACTIVE. The MongoDB CDC pipeline (OnPrem → US-W → US-E) serves as the primary demo path for DR replication.

## Consequences

### Positive
- MongoDB pipeline fully validates the CDC → MSK → cross-region replication architecture
- DSQL can be activated later without changing the pipeline configuration

### Negative
- PostgreSQL → DSQL replication path is not demonstrable
- JDBC Sink connector runs but has no valid target

### Resolution Path
- Investigate Terraform `aws_dsql_cluster` resource for multi-region link configuration
- May require manual linking via AWS console or CLI `dsql create-multi-region-clusters`
