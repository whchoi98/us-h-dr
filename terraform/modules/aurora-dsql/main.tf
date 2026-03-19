# -----------------------------------------------------------------------------
# Aurora DSQL Multi-Region Cluster
# -----------------------------------------------------------------------------
# Aurora DSQL provides serverless, distributed SQL with active-active
# multi-region capability. The primary and linked clusters form a
# multi-region cluster pair with a witness region for quorum.
#
# The multi_region_properties block with witness_region makes each cluster
# part of a multi-region cluster group. Both clusters reference each other
# via the clusters attribute after creation.
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.linked, aws.witness]
    }
  }
}

resource "aws_dsql_cluster" "primary" {
  deletion_protection_enabled = false

  multi_region_properties {
    witness_region = var.witness_region
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_identifier}-primary"
  })
}

resource "aws_dsql_cluster" "linked" {
  provider                    = aws.linked
  deletion_protection_enabled = false

  multi_region_properties {
    witness_region = var.witness_region
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_identifier}-linked"
  })
}
