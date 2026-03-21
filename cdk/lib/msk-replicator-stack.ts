import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface MskReplicatorStackProps extends cdk.StackProps {
  /** ARN of the source MSK cluster (US-W) */
  sourceMskClusterArn: string;
  /** ARN of the target MSK cluster (US-E) */
  targetMskClusterArn: string;
}

/**
 * MSK Replicator stack for cross-region replication from US-W MSK to US-E MSK.
 *
 * Uses CfnReplicator (AWS::MSK::Replicator) to replicate topics between
 * the primary (us-west-2) and DR (us-east-1) MSK clusters.
 */
export class MskReplicatorStack extends cdk.Stack {
  public readonly replicator: cdk.CfnResource;

  constructor(scope: Construct, id: string, props: MskReplicatorStackProps) {
    super(scope, id, props);

    // -------------------------------------------------------------------------
    // IAM Role for MSK Replicator
    // -------------------------------------------------------------------------

    const sourceTopicArn = props.sourceMskClusterArn.replace(':cluster/', ':topic/') + '/*';
    const sourceGroupArn = props.sourceMskClusterArn.replace(':cluster/', ':group/') + '/*';
    const targetTopicArn = props.targetMskClusterArn.replace(':cluster/', ':topic/') + '/*';
    const targetGroupArn = props.targetMskClusterArn.replace(':cluster/', ':group/') + '/*';

    const replicatorRole = new iam.Role(this, 'MskReplicatorRole', {
      roleName: 'dr-lab-msk-replicator-role',
      assumedBy: new iam.ServicePrincipal('kafka.amazonaws.com'),
      inlinePolicies: {
        mskReplicatorAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              sid: 'ClusterAccess',
              actions: [
                'kafka-cluster:Connect',
                'kafka-cluster:DescribeCluster',
                'kafka-cluster:AlterCluster',
              ],
              resources: [props.sourceMskClusterArn, props.targetMskClusterArn],
            }),
            new iam.PolicyStatement({
              sid: 'TopicAccess',
              actions: [
                'kafka-cluster:DescribeTopic',
                'kafka-cluster:CreateTopic',
                'kafka-cluster:AlterTopic',
                'kafka-cluster:WriteData',
                'kafka-cluster:ReadData',
              ],
              resources: [sourceTopicArn, targetTopicArn],
            }),
            new iam.PolicyStatement({
              sid: 'GroupAccess',
              actions: [
                'kafka-cluster:AlterGroup',
                'kafka-cluster:DescribeGroup',
              ],
              resources: [sourceGroupArn, targetGroupArn],
            }),
          ],
        }),
      },
    });

    // -------------------------------------------------------------------------
    // MSK Replicator (US-W -> US-E)
    // -------------------------------------------------------------------------

    this.replicator = new cdk.CfnResource(this, 'MskReplicator', {
      type: 'AWS::MSK::Replicator',
      properties: {
        ReplicatorName: 'dr-lab-msk-replicator',
        Description: 'Cross-region MSK replication from US-W to US-E',
        ServiceExecutionRoleArn: replicatorRole.roleArn,
        KafkaClusters: [
          {
            AmazonMskCluster: {
              MskClusterArn: props.sourceMskClusterArn,
            },
            VpcConfig: {
              // VPC config is derived from the MSK cluster's configuration
              SubnetIds: [],
              SecurityGroupIds: [],
            },
          },
          {
            AmazonMskCluster: {
              MskClusterArn: props.targetMskClusterArn,
            },
            VpcConfig: {
              SubnetIds: [],
              SecurityGroupIds: [],
            },
          },
        ],
        ReplicationInfoList: [
          {
            SourceKafkaClusterArn: props.sourceMskClusterArn,
            TargetKafkaClusterArn: props.targetMskClusterArn,
            TargetCompressionType: 'GZIP',
            TopicReplication: {
              TopicsToReplicate: ['.*'],
              TopicsToExclude: ['__.*'],
              CopyTopicConfigurations: true,
              CopyAccessControlListsForTopics: true,
              DetectAndCopyNewTopics: true,
            },
            ConsumerGroupReplication: {
              ConsumerGroupsToReplicate: ['.*'],
              ConsumerGroupsToExclude: ['__.*'],
              SynchroniseConsumerGroupOffsets: true,
              DetectAndCopyNewConsumerGroups: true,
            },
          },
        ],
        CurrentVersion: '',
        Tags: [
          { Key: 'Name', Value: 'dr-lab-msk-replicator' },
          { Key: 'Component', Value: 'replication' },
        ],
      },
    });

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, 'ReplicatorArn', {
      value: this.replicator.ref,
      description: 'MSK Replicator ARN',
    });

    cdk.Tags.of(this).add('Component', 'msk-replicator');
  }
}
