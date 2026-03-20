import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { Config } from './config';

export interface EksStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  privateSubnets: ec2.ISubnet[];
  regionLabel: string;
}

export class EksStack extends cdk.Stack {
  public readonly clusterRole: iam.Role;
  public readonly nodeRole: iam.Role;
  public readonly nodeSecurityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: EksStackProps) {
    super(scope, id, props);

    const clusterName = `dr-lab-${props.regionLabel.toLowerCase()}-eks`;

    // -------------------------------------------------------------------------
    // IAM Role for EKS Cluster
    // -------------------------------------------------------------------------

    this.clusterRole = new iam.Role(this, 'EksClusterRole', {
      roleName: `${clusterName}-cluster-role`,
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSVPCResourceController'),
      ],
    });

    // -------------------------------------------------------------------------
    // IAM Role for EKS Node Group
    // -------------------------------------------------------------------------

    this.nodeRole = new iam.Role(this, 'EksNodeRole', {
      roleName: `${clusterName}-node-role`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSWorkerNodePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKS_CNI_Policy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // -------------------------------------------------------------------------
    // Security Group for EKS Nodes
    // -------------------------------------------------------------------------

    this.nodeSecurityGroup = new ec2.SecurityGroup(this, 'EksNodeSg', {
      vpc: props.vpc,
      description: `EKS node SG for ${clusterName}`,
      allowAllOutbound: true,
    });

    // Allow nodes to communicate with each other
    this.nodeSecurityGroup.addIngressRule(
      this.nodeSecurityGroup,
      ec2.Port.allTraffic(),
      'Allow node-to-node communication'
    );

    // Allow kubelet API from control plane
    this.nodeSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcpRange(1025, 65535),
      'Allow kubelet and NodePort from VPC'
    );

    // Allow API server access from VPC
    this.nodeSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(props.vpc.vpcCidrBlock),
      ec2.Port.tcp(443),
      'Allow HTTPS from VPC for API server'
    );

    // -------------------------------------------------------------------------
    // eksctl Config YAML Output
    // -------------------------------------------------------------------------

    const subnetIds = props.privateSubnets.map(s => s.subnetId);
    const eksctlConfig = [
      'apiVersion: eksctl.io/v1alpha5',
      'kind: ClusterConfig',
      'metadata:',
      `  name: ${clusterName}`,
      `  region: ${this.region}`,
      `  version: "${Config.eks.version}"`,
      'vpc:',
      '  subnets:',
      '    private:',
      ...subnetIds.map((id, i) => `      subnet-${i}: { id: ${id} }`),
      '  securityGroup: ' + this.nodeSecurityGroup.securityGroupId,
      'managedNodeGroups:',
      '  - name: workers',
      `    instanceType: ${Config.eks.nodeType}`,
      `    desiredCapacity: ${Config.eks.nodeCount}`,
      `    minSize: ${Math.floor(Config.eks.nodeCount / 2)}`,
      `    maxSize: ${Config.eks.nodeCount * 2}`,
      '    volumeSize: 100',
      '    volumeType: gp3',
      `    iam:`,
      `      instanceRoleARN: ${this.nodeRole.roleArn}`,
    ].join('\n');

    new cdk.CfnOutput(this, 'EksctlConfig', {
      value: eksctlConfig,
      description: `eksctl config for ${clusterName}`,
    });

    new cdk.CfnOutput(this, 'ClusterRoleArn', {
      value: this.clusterRole.roleArn,
    });

    new cdk.CfnOutput(this, 'NodeRoleArn', {
      value: this.nodeRole.roleArn,
    });

    new cdk.CfnOutput(this, 'NodeSecurityGroupId', {
      value: this.nodeSecurityGroup.securityGroupId,
    });

    cdk.Tags.of(this).add('Component', 'eks');
    cdk.Tags.of(this).add('Cluster', clusterName);
  }
}
