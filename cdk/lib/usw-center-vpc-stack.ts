import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { Config } from './config';
import { DrVpc } from './constructs/vpc-construct';

export class UswCenterVpcStack extends cdk.Stack {
  public readonly drVpc: DrVpc;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const cfg = Config.vpcs.uswCenter;

    this.drVpc = new DrVpc(this, 'UswCenterVpc', {
      vpcName: cfg.name,
      cidr: cfg.cidr,
      publicSubnetCidrs: cfg.publicSubnets,
      privateSubnetCidrs: cfg.privateSubnets,
      dataSubnetCidrs: cfg.dataSubnets,
      tgwSubnetCidrs: cfg.tgwSubnets,
    });

    cdk.Tags.of(this).add('VPC', 'us-w-center');
    cdk.Tags.of(this).add('Component', 'network');
  }
}
