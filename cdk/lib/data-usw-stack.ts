import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { Config } from './config';

export interface DataUswStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  dataSubnets: ec2.ISubnet[];
  privateSubnets: ec2.ISubnet[];
}

export class DataUswStack extends cdk.Stack {
  public readonly mongoInstance: ec2.Instance;
  public readonly mskClusterArn: string;
  public readonly mskSg: ec2.SecurityGroup;
  public readonly mongoSg: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: DataUswStackProps) {
    super(scope, id, props);

    const al2023Arm64 = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    });

    // Shared IAM role for data instances
    const dataRole = new iam.Role(this, 'DataInstanceRole', {
      roleName: 'dr-lab-usw-data-role',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // -------------------------------------------------------------------------
    // Security Groups
    // -------------------------------------------------------------------------

    // MongoDB SG
    this.mongoSg = new ec2.SecurityGroup(this, 'MongoSg', {
      vpc: props.vpc,
      description: 'MongoDB security group (US-W)',
      allowAllOutbound: true,
    });
    this.mongoSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(27017),
      'MongoDB from VPC'
    );

    // MSK SG
    this.mskSg = new ec2.SecurityGroup(this, 'MskSg', {
      vpc: props.vpc,
      description: 'MSK cluster security group (US-W)',
      allowAllOutbound: true,
    });
    this.mskSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(9092),
      'Kafka PLAINTEXT from VPC'
    );
    this.mskSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(9094),
      'Kafka TLS from VPC'
    );
    this.mskSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(9098),
      'Kafka IAM from VPC'
    );
    this.mskSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(2181),
      'ZooKeeper from VPC'
    );
    this.mskSg.addIngressRule(
      this.mskSg,
      ec2.Port.allTraffic(),
      'Inter-broker traffic'
    );

    // MSK Connect SG
    const mskConnectSg = new ec2.SecurityGroup(this, 'MskConnectSg', {
      vpc: props.vpc,
      description: 'MSK Connect security group (US-W)',
      allowAllOutbound: true,
    });
    this.mskSg.addIngressRule(
      mskConnectSg,
      ec2.Port.tcp(9098),
      'MSK from MSK Connect (IAM)'
    );
    this.mongoSg.addIngressRule(
      mskConnectSg,
      ec2.Port.tcp(27017),
      'MongoDB from MSK Connect'
    );

    // -------------------------------------------------------------------------
    // MongoDB EC2
    // -------------------------------------------------------------------------

    this.mongoInstance = new ec2.Instance(this, 'MongoInstance', {
      vpc: props.vpc,
      vpcSubnets: { subnets: [props.dataSubnets[0]] },
      instanceType: new ec2.InstanceType(Config.db.instanceType),
      machineImage: al2023Arm64,
      role: dataRole,
      securityGroup: this.mongoSg,
      blockDevices: [{
        deviceName: '/dev/xvda',
        volume: ec2.BlockDeviceVolume.ebs(200, {
          volumeType: ec2.EbsDeviceVolumeType.GP3,
          encrypted: true,
        }),
      }],
    });
    cdk.Tags.of(this.mongoInstance).add('Name', 'dr-lab-usw-mongodb');

    // -------------------------------------------------------------------------
    // MSK Cluster (4x kafka.m7g.xlarge, TLS+IAM, encrypted)
    // -------------------------------------------------------------------------

    const mskCluster = new cdk.CfnResource(this, 'MskCluster', {
      type: 'AWS::MSK::Cluster',
      properties: {
        ClusterName: 'dr-lab-usw-msk',
        KafkaVersion: '3.6.0',
        NumberOfBrokerNodes: Config.msk.brokerCount,
        BrokerNodeGroupInfo: {
          InstanceType: Config.msk.instanceType,
          ClientSubnets: props.dataSubnets.map(s => s.subnetId),
          SecurityGroups: [this.mskSg.securityGroupId],
          StorageInfo: {
            EBSStorageInfo: {
              VolumeSize: 500,
            },
          },
        },
        ClientAuthentication: {
          Sasl: {
            Iam: { Enabled: true },
          },
          Tls: {
            Enabled: true,
          },
        },
        EncryptionInfo: {
          EncryptionInTransit: {
            ClientBroker: 'TLS',
            InCluster: true,
          },
          EncryptionAtRest: {
            DataVolumeKMSKeyId: 'alias/aws/kafka',
          },
        },
        EnhancedMonitoring: 'PER_TOPIC_PER_BROKER',
        Tags: {
          Name: 'dr-lab-usw-msk',
          Component: 'data-usw',
        },
      },
    });

    this.mskClusterArn = mskCluster.getAtt('Arn').toString();

    // -------------------------------------------------------------------------
    // MSK Connect – IAM Role for connectors
    // -------------------------------------------------------------------------

    const mskConnectRole = new iam.Role(this, 'MskConnectRole', {
      roleName: 'dr-lab-usw-msk-connect-role',
      assumedBy: new iam.ServicePrincipal('kafkaconnect.amazonaws.com'),
      inlinePolicies: {
        mskAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: [
                'kafka-cluster:Connect',
                'kafka-cluster:DescribeCluster',
                'kafka-cluster:ReadData',
                'kafka-cluster:WriteData',
                'kafka-cluster:CreateTopic',
                'kafka-cluster:DescribeTopic',
                'kafka-cluster:AlterGroup',
                'kafka-cluster:DescribeGroup',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // -------------------------------------------------------------------------
    // MSK Connect – JDBC Sink Connector
    // -------------------------------------------------------------------------

    new cdk.CfnResource(this, 'JdbcSinkConnector', {
      type: 'AWS::KafkaConnect::Connector',
      properties: {
        ConnectorName: 'dr-lab-usw-jdbc-sink',
        KafkaCluster: {
          ApacheKafkaCluster: {
            BootstrapServers: cdk.Fn.join(',', [
              cdk.Fn.sub('b-1.${ClusterName}.kafka.${AWS::Region}.amazonaws.com:9098', {
                ClusterName: 'dr-lab-usw-msk',
              }),
            ]),
            Vpc: {
              SecurityGroups: [mskConnectSg.securityGroupId],
              Subnets: props.privateSubnets.map(s => s.subnetId),
            },
          },
        },
        KafkaClusterClientAuthentication: { AuthenticationType: 'IAM' },
        KafkaClusterEncryptionInTransit: { EncryptionType: 'TLS' },
        KafkaConnectVersion: '2.7.1',
        Capacity: {
          ProvisionedCapacity: {
            McuCount: 1,
            WorkerCount: 1,
          },
        },
        ServiceExecutionRoleArn: mskConnectRole.roleArn,
        ConnectorConfiguration: {
          'connector.class': 'io.confluent.connect.jdbc.JdbcSinkConnector',
          'tasks.max': '2',
          'topics': 'dbserver1.public.orders,dbserver1.public.customers',
          'connection.url': 'jdbc:postgresql://aurora-dsql-endpoint:5432/drlab',
          'auto.create': 'true',
          'insert.mode': 'upsert',
          'pk.mode': 'record_key',
          'key.converter': 'org.apache.kafka.connect.json.JsonConverter',
          'value.converter': 'org.apache.kafka.connect.json.JsonConverter',
        },
        Plugins: [{
          CustomPlugin: {
            CustomPluginArn: cdk.Fn.sub('arn:aws:kafkaconnect:${AWS::Region}:${AWS::AccountId}:custom-plugin/jdbc-sink-plugin/*'),
            Revision: 1,
          },
        }],
      },
    });

    // -------------------------------------------------------------------------
    // MSK Connect – MongoDB Sink Connector
    // -------------------------------------------------------------------------

    new cdk.CfnResource(this, 'MongoSinkConnector', {
      type: 'AWS::KafkaConnect::Connector',
      properties: {
        ConnectorName: 'dr-lab-usw-mongo-sink',
        KafkaCluster: {
          ApacheKafkaCluster: {
            BootstrapServers: cdk.Fn.join(',', [
              cdk.Fn.sub('b-1.${ClusterName}.kafka.${AWS::Region}.amazonaws.com:9098', {
                ClusterName: 'dr-lab-usw-msk',
              }),
            ]),
            Vpc: {
              SecurityGroups: [mskConnectSg.securityGroupId],
              Subnets: props.privateSubnets.map(s => s.subnetId),
            },
          },
        },
        KafkaClusterClientAuthentication: { AuthenticationType: 'IAM' },
        KafkaClusterEncryptionInTransit: { EncryptionType: 'TLS' },
        KafkaConnectVersion: '2.7.1',
        Capacity: {
          ProvisionedCapacity: {
            McuCount: 1,
            WorkerCount: 1,
          },
        },
        ServiceExecutionRoleArn: mskConnectRole.roleArn,
        ConnectorConfiguration: {
          'connector.class': 'com.mongodb.kafka.connect.MongoSinkConnector',
          'tasks.max': '2',
          'topics': 'dbserver1.inventory.products,dbserver1.inventory.inventory',
          'connection.uri': `mongodb://${this.mongoInstance.instancePrivateIp}:27017`,
          'database': 'drlab',
          'key.converter': 'org.apache.kafka.connect.json.JsonConverter',
          'value.converter': 'org.apache.kafka.connect.json.JsonConverter',
        },
        Plugins: [{
          CustomPlugin: {
            CustomPluginArn: cdk.Fn.sub('arn:aws:kafkaconnect:${AWS::Region}:${AWS::AccountId}:custom-plugin/mongo-sink-plugin/*'),
            Revision: 1,
          },
        }],
      },
    });

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, 'MskClusterArn', {
      value: this.mskClusterArn,
      description: 'MSK Cluster ARN (US-W)',
    });

    new cdk.CfnOutput(this, 'MongoPrivateIp', {
      value: this.mongoInstance.instancePrivateIp,
    });

    cdk.Tags.of(this).add('Component', 'data-usw');
  }
}
