import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { Config } from './config';

export interface VscodeServerStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  privateSubnet: ec2.ISubnet;
  albSecurityGroup: ec2.ISecurityGroup;
}

export class VscodeServerStack extends cdk.Stack {
  public readonly instance: ec2.Instance;
  public readonly securityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: VscodeServerStackProps) {
    super(scope, id, props);

    // -------------------------------------------------------------------------
    // IAM Role for VSCode Server
    // -------------------------------------------------------------------------

    const role = new iam.Role(this, 'VscodeRole', {
      roleName: 'dr-lab-vscode-server-role',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // Additional permissions for EKS management
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'eks:DescribeCluster',
        'eks:ListClusters',
        'eks:AccessKubernetesApi',
        'ecr:GetAuthorizationToken',
        'ecr:BatchGetImage',
        'ecr:GetDownloadUrlForLayer',
      ],
      resources: ['*'],
    }));

    // -------------------------------------------------------------------------
    // Security Group
    // -------------------------------------------------------------------------

    this.securityGroup = new ec2.SecurityGroup(this, 'VscodeSg', {
      vpc: props.vpc,
      description: 'VSCode Server SG - allows 8888 from ALB',
      allowAllOutbound: true,
    });

    // Allow code-server port from ALB security group
    this.securityGroup.addIngressRule(
      ec2.Peer.securityGroupId(props.albSecurityGroup.securityGroupId),
      ec2.Port.tcp(8888),
      'Allow code-server from ALB'
    );

    // -------------------------------------------------------------------------
    // UserData
    // -------------------------------------------------------------------------

    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'set -euxo pipefail',
      '',
      '# System updates',
      'dnf update -y',
      'dnf install -y git jq tar gzip unzip wget curl',
      '',
      '# Install Docker',
      'dnf install -y docker',
      'systemctl enable docker && systemctl start docker',
      'usermod -aG docker ec2-user',
      '',
      '# Install kubectl',
      'curl -LO "https://dl.k8s.io/release/v1.33.0/bin/linux/arm64/kubectl"',
      'install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl',
      '',
      '# Install eksctl',
      'curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_Linux_arm64.tar.gz"',
      'tar -xzf eksctl_Linux_arm64.tar.gz -C /usr/local/bin',
      '',
      '# Install Helm',
      'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash',
      '',
      '# Install code-server',
      'curl -fsSL https://code-server.dev/install.sh | sh',
      'mkdir -p /home/ec2-user/.config/code-server',
      'cat > /home/ec2-user/.config/code-server/config.yaml <<CSCFG',
      'bind-addr: 0.0.0.0:8888',
      'auth: password',
      'password: changeme-dr-lab',
      'cert: false',
      'CSCFG',
      'chown -R ec2-user:ec2-user /home/ec2-user/.config',
      '',
      '# Install AWS CLI v2 (ARM64)',
      'curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"',
      'unzip -q awscliv2.zip && ./aws/install',
      '',
      '# Install k9s',
      'curl -sLO https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_arm64.tar.gz',
      'tar -xzf k9s_Linux_arm64.tar.gz -C /usr/local/bin k9s',
      '',
      '# Start code-server as ec2-user',
      'cat > /etc/systemd/system/code-server.service <<SVCUNIT',
      '[Unit]',
      'Description=code-server',
      'After=network.target',
      '[Service]',
      'Type=simple',
      'User=ec2-user',
      'ExecStart=/usr/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml',
      'Restart=always',
      '[Install]',
      'WantedBy=multi-user.target',
      'SVCUNIT',
      'systemctl daemon-reload',
      'systemctl enable code-server && systemctl start code-server',
    );

    // -------------------------------------------------------------------------
    // EC2 Instance – AL2023 ARM64, m7g.xlarge
    // -------------------------------------------------------------------------

    const al2023Arm64 = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    });

    this.instance = new ec2.Instance(this, 'VscodeInstance', {
      vpc: props.vpc,
      vpcSubnets: { subnets: [props.privateSubnet] },
      instanceType: new ec2.InstanceType(Config.vscode.instanceType),
      machineImage: al2023Arm64,
      role: role,
      securityGroup: this.securityGroup,
      userData: userData,
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(100, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
    });

    cdk.Tags.of(this.instance).add('Name', 'dr-lab-vscode-server');

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, 'VscodeInstanceId', {
      value: this.instance.instanceId,
      description: 'VSCode Server instance ID',
    });

    new cdk.CfnOutput(this, 'VscodePrivateIp', {
      value: this.instance.instancePrivateIp,
      description: 'VSCode Server private IP',
    });

    cdk.Tags.of(this).add('Component', 'vscode-server');
  }
}
