import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { Config } from './config';

export interface DataOnpremStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  dataSubnets: ec2.ISubnet[];
}

export class DataOnpremStack extends cdk.Stack {
  public readonly postgresInstance: ec2.Instance;
  public readonly mongoInstance: ec2.Instance;
  public readonly kafkaInstances: ec2.Instance[];
  public readonly debeziumInstance: ec2.Instance;
  public readonly mirrorMakerInstance: ec2.Instance;

  public readonly postgresSg: ec2.SecurityGroup;
  public readonly mongoSg: ec2.SecurityGroup;
  public readonly kafkaSg: ec2.SecurityGroup;
  public readonly debeziumSg: ec2.SecurityGroup;
  public readonly mirrorMakerSg: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: DataOnpremStackProps) {
    super(scope, id, props);

    const al2023Arm64 = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    });

    // Shared IAM role for data instances
    const dataRole = new iam.Role(this, 'DataInstanceRole', {
      roleName: 'dr-lab-onprem-data-role',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // -------------------------------------------------------------------------
    // Security Groups (Section 6.1)
    // -------------------------------------------------------------------------

    // PostgreSQL SG
    this.postgresSg = new ec2.SecurityGroup(this, 'PostgresSg', {
      vpc: props.vpc,
      description: 'PostgreSQL security group',
      allowAllOutbound: true,
    });
    this.postgresSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(5432),
      'PostgreSQL from VPC'
    );

    // MongoDB SG
    this.mongoSg = new ec2.SecurityGroup(this, 'MongoSg', {
      vpc: props.vpc,
      description: 'MongoDB security group',
      allowAllOutbound: true,
    });
    this.mongoSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(27017),
      'MongoDB from VPC'
    );

    // Kafka SG
    this.kafkaSg = new ec2.SecurityGroup(this, 'KafkaSg', {
      vpc: props.vpc,
      description: 'Kafka security group',
      allowAllOutbound: true,
    });
    this.kafkaSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(9092),
      'Kafka PLAINTEXT from VPC'
    );
    this.kafkaSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(9093),
      'Kafka TLS from VPC'
    );
    this.kafkaSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(2181),
      'ZooKeeper from VPC'
    );
    // Allow inter-broker communication
    this.kafkaSg.addIngressRule(
      this.kafkaSg,
      ec2.Port.allTraffic(),
      'Inter-broker traffic'
    );

    // Debezium Connect SG
    this.debeziumSg = new ec2.SecurityGroup(this, 'DebeziumSg', {
      vpc: props.vpc,
      description: 'Debezium Connect security group',
      allowAllOutbound: true,
    });
    this.debeziumSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(8083),
      'Kafka Connect REST from VPC'
    );

    // MirrorMaker 2 SG
    this.mirrorMakerSg = new ec2.SecurityGroup(this, 'MirrorMakerSg', {
      vpc: props.vpc,
      description: 'MirrorMaker 2 security group',
      allowAllOutbound: true,
    });
    this.mirrorMakerSg.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(8083),
      'MM2 Connect REST from VPC'
    );

    // Allow Debezium to access PostgreSQL and Kafka
    this.postgresSg.addIngressRule(
      this.debeziumSg,
      ec2.Port.tcp(5432),
      'PostgreSQL from Debezium'
    );
    this.kafkaSg.addIngressRule(
      this.debeziumSg,
      ec2.Port.tcp(9092),
      'Kafka from Debezium'
    );

    // Allow MirrorMaker to access Kafka
    this.kafkaSg.addIngressRule(
      this.mirrorMakerSg,
      ec2.Port.tcp(9092),
      'Kafka from MirrorMaker'
    );

    // -------------------------------------------------------------------------
    // PostgreSQL EC2 (data subnet a)
    // -------------------------------------------------------------------------

    this.postgresInstance = new ec2.Instance(this, 'PostgresInstance', {
      vpc: props.vpc,
      vpcSubnets: { subnets: [props.dataSubnets[0]] },
      instanceType: new ec2.InstanceType(Config.db.instanceType),
      machineImage: al2023Arm64,
      role: dataRole,
      securityGroup: this.postgresSg,
      blockDevices: [{
        deviceName: '/dev/xvda',
        volume: ec2.BlockDeviceVolume.ebs(200, {
          volumeType: ec2.EbsDeviceVolumeType.GP3,
          encrypted: true,
        }),
      }],
    });
    cdk.Tags.of(this.postgresInstance).add('Name', 'dr-lab-onprem-postgres');

    // -------------------------------------------------------------------------
    // MongoDB EC2 (data subnet b)
    // -------------------------------------------------------------------------

    this.mongoInstance = new ec2.Instance(this, 'MongoInstance', {
      vpc: props.vpc,
      vpcSubnets: { subnets: [props.dataSubnets[1]] },
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
    cdk.Tags.of(this.mongoInstance).add('Name', 'dr-lab-onprem-mongodb');

    // -------------------------------------------------------------------------
    // Kafka EC2 x4 (2 in data subnet a, 2 in data subnet b)
    // -------------------------------------------------------------------------

    this.kafkaInstances = [];
    for (let i = 0; i < Config.kafka.brokerCount; i++) {
      const subnetIndex = i % 2; // alternate between subnets
      const instance = new ec2.Instance(this, `KafkaInstance${i}`, {
        vpc: props.vpc,
        vpcSubnets: { subnets: [props.dataSubnets[subnetIndex]] },
        instanceType: new ec2.InstanceType(Config.kafka.instanceType),
        machineImage: al2023Arm64,
        role: dataRole,
        securityGroup: this.kafkaSg,
        blockDevices: [{
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(500, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        }],
      });
      cdk.Tags.of(instance).add('Name', `dr-lab-onprem-kafka-${i}`);
      this.kafkaInstances.push(instance);
    }

    // -------------------------------------------------------------------------
    // Debezium Connect EC2
    // -------------------------------------------------------------------------

    this.debeziumInstance = new ec2.Instance(this, 'DebeziumInstance', {
      vpc: props.vpc,
      vpcSubnets: { subnets: [props.dataSubnets[0]] },
      instanceType: new ec2.InstanceType('m7g.large'),
      machineImage: al2023Arm64,
      role: dataRole,
      securityGroup: this.debeziumSg,
      blockDevices: [{
        deviceName: '/dev/xvda',
        volume: ec2.BlockDeviceVolume.ebs(100, {
          volumeType: ec2.EbsDeviceVolumeType.GP3,
          encrypted: true,
        }),
      }],
    });
    cdk.Tags.of(this.debeziumInstance).add('Name', 'dr-lab-onprem-debezium');

    // -------------------------------------------------------------------------
    // MirrorMaker 2 EC2
    // -------------------------------------------------------------------------

    this.mirrorMakerInstance = new ec2.Instance(this, 'MirrorMakerInstance', {
      vpc: props.vpc,
      vpcSubnets: { subnets: [props.dataSubnets[1]] },
      instanceType: new ec2.InstanceType('m7g.large'),
      machineImage: al2023Arm64,
      role: dataRole,
      securityGroup: this.mirrorMakerSg,
      blockDevices: [{
        deviceName: '/dev/xvda',
        volume: ec2.BlockDeviceVolume.ebs(100, {
          volumeType: ec2.EbsDeviceVolumeType.GP3,
          encrypted: true,
        }),
      }],
    });
    cdk.Tags.of(this.mirrorMakerInstance).add('Name', 'dr-lab-onprem-mirrormaker2');

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, 'PostgresPrivateIp', {
      value: this.postgresInstance.instancePrivateIp,
    });
    new cdk.CfnOutput(this, 'MongoPrivateIp', {
      value: this.mongoInstance.instancePrivateIp,
    });
    this.kafkaInstances.forEach((inst, i) => {
      new cdk.CfnOutput(this, `KafkaPrivateIp${i}`, {
        value: inst.instancePrivateIp,
      });
    });
    new cdk.CfnOutput(this, 'DebeziumPrivateIp', {
      value: this.debeziumInstance.instancePrivateIp,
    });
    new cdk.CfnOutput(this, 'MirrorMakerPrivateIp', {
      value: this.mirrorMakerInstance.instancePrivateIp,
    });

    cdk.Tags.of(this).add('Component', 'data-onprem');
  }
}
