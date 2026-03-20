import * as cdk from 'aws-cdk-lib';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cw_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

export interface MonitoringStackProps extends cdk.StackProps {
  regionLabel: string;
  mskClusterName?: string;
  eksClusterName?: string;
}

export class MonitoringStack extends cdk.Stack {
  public readonly alarmTopic: sns.Topic;
  public readonly criticalTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: MonitoringStackProps) {
    super(scope, id, props);

    // -------------------------------------------------------------------------
    // SNS Topics
    // -------------------------------------------------------------------------

    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `dr-lab-${props.regionLabel.toLowerCase()}-alarms`,
      displayName: `DR Lab ${props.regionLabel} Alarms`,
    });

    this.criticalTopic = new sns.Topic(this, 'CriticalTopic', {
      topicName: `dr-lab-${props.regionLabel.toLowerCase()}-critical`,
      displayName: `DR Lab ${props.regionLabel} Critical Alarms`,
    });

    // -------------------------------------------------------------------------
    // MSK Alarms
    // -------------------------------------------------------------------------

    if (props.mskClusterName) {
      // Active controller count (should be exactly 1)
      const activeControllerAlarm = new cloudwatch.Alarm(this, 'MskActiveControllerAlarm', {
        alarmName: `${props.regionLabel}-msk-active-controller`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/Kafka',
          metricName: 'ActiveControllerCount',
          dimensionsMap: { 'Cluster Name': props.mskClusterName },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 1,
        evaluationPeriods: 3,
        comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.BREACHING,
        alarmDescription: `MSK ${props.regionLabel}: No active controller detected`,
      });
      activeControllerAlarm.addAlarmAction(new cw_actions.SnsAction(this.criticalTopic));

      // Offline partitions (should be 0)
      const offlinePartitionsAlarm = new cloudwatch.Alarm(this, 'MskOfflinePartitionsAlarm', {
        alarmName: `${props.regionLabel}-msk-offline-partitions`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/Kafka',
          metricName: 'OfflinePartitionsCount',
          dimensionsMap: { 'Cluster Name': props.mskClusterName },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 0,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: `MSK ${props.regionLabel}: Offline partitions detected`,
      });
      offlinePartitionsAlarm.addAlarmAction(new cw_actions.SnsAction(this.criticalTopic));

      // Under-replicated partitions
      const underReplicatedAlarm = new cloudwatch.Alarm(this, 'MskUnderReplicatedAlarm', {
        alarmName: `${props.regionLabel}-msk-under-replicated-partitions`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/Kafka',
          metricName: 'UnderReplicatedPartitions',
          dimensionsMap: { 'Cluster Name': props.mskClusterName },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 0,
        evaluationPeriods: 3,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: `MSK ${props.regionLabel}: Under-replicated partitions`,
      });
      underReplicatedAlarm.addAlarmAction(new cw_actions.SnsAction(this.alarmTopic));

      // Disk usage > 85%
      const diskUsageAlarm = new cloudwatch.Alarm(this, 'MskDiskUsageAlarm', {
        alarmName: `${props.regionLabel}-msk-disk-usage`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/Kafka',
          metricName: 'KafkaDataLogsDiskUsed',
          dimensionsMap: { 'Cluster Name': props.mskClusterName },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 85,
        evaluationPeriods: 3,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: `MSK ${props.regionLabel}: Disk usage > 85%`,
      });
      diskUsageAlarm.addAlarmAction(new cw_actions.SnsAction(this.alarmTopic));
    }

    // -------------------------------------------------------------------------
    // EKS Alarms
    // -------------------------------------------------------------------------

    if (props.eksClusterName) {
      // Cluster failed node count
      const eksNodeAlarm = new cloudwatch.Alarm(this, 'EksNodeAlarm', {
        alarmName: `${props.regionLabel}-eks-node-not-ready`,
        metric: new cloudwatch.Metric({
          namespace: 'ContainerInsights',
          metricName: 'cluster_failed_node_count',
          dimensionsMap: { ClusterName: props.eksClusterName },
          statistic: 'Maximum',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 0,
        evaluationPeriods: 3,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: `EKS ${props.regionLabel}: Failed nodes detected`,
      });
      eksNodeAlarm.addAlarmAction(new cw_actions.SnsAction(this.criticalTopic));

      // Pod restarts
      const eksPodRestartAlarm = new cloudwatch.Alarm(this, 'EksPodRestartAlarm', {
        alarmName: `${props.regionLabel}-eks-pod-restarts`,
        metric: new cloudwatch.Metric({
          namespace: 'ContainerInsights',
          metricName: 'pod_number_of_container_restarts',
          dimensionsMap: { ClusterName: props.eksClusterName },
          statistic: 'Sum',
          period: cdk.Duration.minutes(15),
        }),
        threshold: 10,
        evaluationPeriods: 2,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: `EKS ${props.regionLabel}: Excessive pod restarts`,
      });
      eksPodRestartAlarm.addAlarmAction(new cw_actions.SnsAction(this.alarmTopic));

      // CPU utilization
      const eksCpuAlarm = new cloudwatch.Alarm(this, 'EksCpuAlarm', {
        alarmName: `${props.regionLabel}-eks-cpu-utilization`,
        metric: new cloudwatch.Metric({
          namespace: 'ContainerInsights',
          metricName: 'node_cpu_utilization',
          dimensionsMap: { ClusterName: props.eksClusterName },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 80,
        evaluationPeriods: 6,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: `EKS ${props.regionLabel}: High CPU utilization > 80%`,
      });
      eksCpuAlarm.addAlarmAction(new cw_actions.SnsAction(this.alarmTopic));
    }

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, 'AlarmTopicArn', {
      value: this.alarmTopic.topicArn,
    });

    new cdk.CfnOutput(this, 'CriticalTopicArn', {
      value: this.criticalTopic.topicArn,
    });

    cdk.Tags.of(this).add('Component', 'monitoring');
    cdk.Tags.of(this).add('Region', props.regionLabel);
  }
}
