import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';

export interface DrVpcProps {
  vpcName: string;
  cidr: string;
  publicSubnetCidrs: string[];
  privateSubnetCidrs: string[];
  dataSubnetCidrs: string[];
  tgwSubnetCidrs: string[];
  maxAzs?: number;
}

export class DrVpc extends Construct {
  public readonly vpc: ec2.Vpc;
  public readonly publicSubnets: ec2.ISubnet[];
  public readonly privateSubnets: ec2.ISubnet[];
  public readonly dataSubnets: ec2.ISubnet[];
  public readonly tgwSubnets: ec2.ISubnet[];

  constructor(scope: Construct, id: string, props: DrVpcProps) {
    super(scope, id);

    this.vpc = new ec2.Vpc(this, 'Vpc', {
      vpcName: props.vpcName,
      ipAddresses: ec2.IpAddresses.cidr(props.cidr),
      maxAzs: props.maxAzs ?? 2,
      natGateways: 2,
      subnetConfiguration: [
        { subnetType: ec2.SubnetType.PUBLIC, name: 'Public', cidrMask: 24 },
        { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS, name: 'Private', cidrMask: 20 },
        { subnetType: ec2.SubnetType.PRIVATE_ISOLATED, name: 'Data', cidrMask: 23 },
        { subnetType: ec2.SubnetType.PRIVATE_ISOLATED, name: 'TGW', cidrMask: 24 },
      ],
    });

    this.publicSubnets = this.vpc.publicSubnets;
    this.privateSubnets = this.vpc.privateSubnets;
    this.dataSubnets = this.vpc.isolatedSubnets.filter(s => s.node.id.includes('Data'));
    this.tgwSubnets = this.vpc.isolatedSubnets.filter(s => s.node.id.includes('TGW'));

    // Tag private subnets for EKS internal load balancers
    for (const subnet of this.privateSubnets) {
      cdk.Tags.of(subnet).add('kubernetes.io/role/internal-elb', '1');
    }

    // Tag public subnets for EKS external load balancers
    for (const subnet of this.publicSubnets) {
      cdk.Tags.of(subnet).add('kubernetes.io/role/elb', '1');
    }
  }
}
