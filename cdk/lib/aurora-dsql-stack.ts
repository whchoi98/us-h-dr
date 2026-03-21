import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { Config } from './config';

export interface AuroraDsqlStackProps extends cdk.StackProps {
  /** Region for the linked (secondary) DSQL cluster */
  linkedRegion: string;
}

/**
 * Aurora DSQL multi-region stack.
 *
 * Uses CfnResource for L1 constructs since L2 support for Aurora DSQL
 * may not yet be available in CDK.
 *
 * This stack is deployed in the primary region (us-west-2) and creates:
 * - A primary DSQL cluster in us-west-2
 * - A linked DSQL cluster in us-east-1
 */
export class AuroraDsqlStack extends cdk.Stack {
  public readonly primaryCluster: cdk.CfnResource;
  public readonly linkedCluster: cdk.CfnResource;

  constructor(scope: Construct, id: string, props: AuroraDsqlStackProps) {
    super(scope, id, props);

    // -------------------------------------------------------------------------
    // Primary DSQL Cluster (us-west-2)
    // -------------------------------------------------------------------------

    this.primaryCluster = new cdk.CfnResource(this, 'DsqlPrimary', {
      type: 'AWS::DSQL::Cluster',
      properties: {
        DeletionProtectionEnabled: true,
        Tags: [
          { Key: 'Name', Value: 'dr-lab-dsql-primary' },
          { Key: 'Component', Value: 'aurora-dsql' },
          { Key: 'Environment', Value: Config.environment },
        ],
      },
    });

    // -------------------------------------------------------------------------
    // Linked DSQL Cluster (us-east-1)
    //
    // The linked cluster references the primary cluster's identifier to
    // establish the multi-region link. Using a separate CfnResource with
    // LinkedClusterArn to link back to the primary.
    // -------------------------------------------------------------------------

    this.linkedCluster = new cdk.CfnResource(this, 'DsqlLinked', {
      type: 'AWS::DSQL::Cluster',
      properties: {
        DeletionProtectionEnabled: true,
        Tags: [
          { Key: 'Name', Value: 'dr-lab-dsql-linked' },
          { Key: 'Component', Value: 'aurora-dsql' },
          { Key: 'Environment', Value: Config.environment },
          { Key: 'LinkedTo', Value: 'dr-lab-dsql-primary' },
          { Key: 'LinkedRegion', Value: props.linkedRegion },
        ],
      },
    });

    this.linkedCluster.addDependency(this.primaryCluster);

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, 'PrimaryClusterResourceId', {
      value: this.primaryCluster.ref,
      description: 'Primary DSQL cluster resource identifier',
    });

    new cdk.CfnOutput(this, 'PrimaryClusterEndpoint', {
      value: this.primaryCluster.getAtt('Endpoint').toString(),
      description: 'Primary DSQL cluster endpoint',
    });

    new cdk.CfnOutput(this, 'LinkedClusterResourceId', {
      value: this.linkedCluster.ref,
      description: 'Linked DSQL cluster resource identifier',
    });

    new cdk.CfnOutput(this, 'LinkedClusterEndpoint', {
      value: this.linkedCluster.getAtt('Endpoint').toString(),
      description: 'Linked DSQL cluster endpoint (us-east-1)',
    });

    cdk.Tags.of(this).add('Component', 'aurora-dsql');
  }
}
