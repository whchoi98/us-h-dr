#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Config } from '../lib/config';
import { OnpremVpcStack } from '../lib/onprem-vpc-stack';
import { UswCenterVpcStack } from '../lib/usw-center-vpc-stack';
import { UseCenterVpcStack } from '../lib/use-center-vpc-stack';
import { TgwStack } from '../lib/tgw-stack';
import { TgwEastStack } from '../lib/tgw-east-stack';
import { TgwPeeringStack } from '../lib/tgw-peering-stack';
import { CloudFrontAlbStack } from '../lib/cloudfront-alb-stack';
import { EksStack } from '../lib/eks-stack';
import { VscodeServerStack } from '../lib/vscode-server-stack';
import { DataOnpremStack } from '../lib/data-onprem-stack';
import { DataUswStack } from '../lib/data-usw-stack';
import { AuroraDsqlStack } from '../lib/aurora-dsql-stack';
import { DataUseStack } from '../lib/data-use-stack';
import { MskReplicatorStack } from '../lib/msk-replicator-stack';

const app = new cdk.App();

const envWest = { account: process.env.CDK_DEFAULT_ACCOUNT, region: Config.primaryRegion };
const envEast = { account: process.env.CDK_DEFAULT_ACCOUNT, region: Config.drRegion };

// ---------------------------------------------------------------------------
// Phase 1: VPC Stacks
// ---------------------------------------------------------------------------

const onpremVpc = new OnpremVpcStack(app, 'OnpremVpcStack', { env: envWest });
const uswVpc = new UswCenterVpcStack(app, 'UswCenterVpcStack', { env: envWest });
const useVpc = new UseCenterVpcStack(app, 'UseCenterVpcStack', { env: envEast });

// ---------------------------------------------------------------------------
// Phase 1: Transit Gateway Stacks
// ---------------------------------------------------------------------------

// TGW-West (us-west-2): OnPrem + US-W-CENTER VPC attachments
const tgwWest = new TgwStack(app, 'TgwWestStack', {
  env: envWest,
  tgwName: 'tgw-us-west-2',
  amazonSideAsn: 65000,
  vpcAttachments: [
    {
      name: 'onprem',
      vpc: onpremVpc.drVpc.vpc,
      subnets: onpremVpc.drVpc.tgwSubnets,
      vpcCidr: Config.vpcs.onprem.cidr,
    },
    {
      name: 'usw-center',
      vpc: uswVpc.drVpc.vpc,
      subnets: uswVpc.drVpc.tgwSubnets,
      vpcCidr: Config.vpcs.uswCenter.cidr,
    },
  ],
});
tgwWest.addDependency(onpremVpc);
tgwWest.addDependency(uswVpc);

// TGW-East (us-east-1): US-E-CENTER VPC attachment
const tgwEast = new TgwEastStack(app, 'TgwEastStack', {
  env: envEast,
  tgwName: 'tgw-us-east-1',
  amazonSideAsn: 65001,
  vpcAttachments: [
    {
      name: 'use-center',
      vpc: useVpc.drVpc.vpc,
      subnets: useVpc.drVpc.tgwSubnets,
      vpcCidr: Config.vpcs.useCenter.cidr,
    },
  ],
});
tgwEast.addDependency(useVpc);

// TGW Inter-Region Peering (us-west-2 <-> us-east-1)
// crossRegionReferences is required because this stack (us-west-2) references
// the TGW and route table in TgwEastStack (us-east-1).
const tgwPeering = new TgwPeeringStack(app, 'TgwPeeringStack', {
  env: envWest,
  crossRegionReferences: true,
  requesterTgwId: tgwWest.tgw.ref,
  requesterRouteTableId: tgwWest.routeTable.ref,
  accepterTgwId: tgwEast.tgw.ref,
  accepterRouteTableId: tgwEast.routeTable.ref,
  peerRegion: Config.drRegion,
  // Route US-E-CENTER CIDR via peering from TGW-West
  requesterRouteCidrs: [Config.vpcs.useCenter.cidr],
  // Route OnPrem + US-W-CENTER CIDRs via peering from TGW-East
  accepterRouteCidrs: [Config.vpcs.onprem.cidr, Config.vpcs.uswCenter.cidr],
});
tgwPeering.addDependency(tgwWest);
tgwPeering.addDependency(tgwEast);

// ---------------------------------------------------------------------------
// Phase 2: CloudFront + ALB Stacks
// ---------------------------------------------------------------------------

const cfAlbOnprem = new CloudFrontAlbStack(app, 'CloudFrontAlbOnpremStack', {
  env: envWest,
  vpc: onpremVpc.drVpc.vpc,
  publicSubnets: onpremVpc.drVpc.publicSubnets,
  regionLabel: 'OnPrem',
});
cfAlbOnprem.addDependency(tgwPeering);

const cfAlbUsw = new CloudFrontAlbStack(app, 'CloudFrontAlbUswStack', {
  env: envWest,
  vpc: uswVpc.drVpc.vpc,
  publicSubnets: uswVpc.drVpc.publicSubnets,
  regionLabel: 'US-W',
});
cfAlbUsw.addDependency(tgwPeering);

const cfAlbUse = new CloudFrontAlbStack(app, 'CloudFrontAlbUseStack', {
  env: envEast,
  crossRegionReferences: true,
  vpc: useVpc.drVpc.vpc,
  publicSubnets: useVpc.drVpc.publicSubnets,
  regionLabel: 'US-E',
});
cfAlbUse.addDependency(tgwPeering);

// ---------------------------------------------------------------------------
// Phase 3: EKS Stacks
// ---------------------------------------------------------------------------

const eksOnprem = new EksStack(app, 'EksOnpremStack', {
  env: envWest,
  vpc: onpremVpc.drVpc.vpc,
  privateSubnets: onpremVpc.drVpc.privateSubnets,
  regionLabel: 'OnPrem',
});
eksOnprem.addDependency(cfAlbOnprem);

const eksUsw = new EksStack(app, 'EksUswStack', {
  env: envWest,
  vpc: uswVpc.drVpc.vpc,
  privateSubnets: uswVpc.drVpc.privateSubnets,
  regionLabel: 'US-W',
});
eksUsw.addDependency(cfAlbUsw);

const eksUse = new EksStack(app, 'EksUseStack', {
  env: envEast,
  vpc: useVpc.drVpc.vpc,
  privateSubnets: useVpc.drVpc.privateSubnets,
  regionLabel: 'US-E',
});
eksUse.addDependency(cfAlbUse);

// ---------------------------------------------------------------------------
// Phase 3: VSCode Server (OnPrem only)
// ---------------------------------------------------------------------------

const vscodeServer = new VscodeServerStack(app, 'VscodeServerStack', {
  env: envWest,
  vpc: onpremVpc.drVpc.vpc,
  privateSubnet: onpremVpc.drVpc.privateSubnets[0],
  albSecurityGroup: cfAlbOnprem.albSecurityGroup,
});
vscodeServer.addDependency(eksOnprem);

// ---------------------------------------------------------------------------
// Phase 4: Data Stacks – OnPrem
// ---------------------------------------------------------------------------

const dataOnprem = new DataOnpremStack(app, 'DataOnpremStack', {
  env: envWest,
  vpc: onpremVpc.drVpc.vpc,
  dataSubnets: onpremVpc.drVpc.dataSubnets,
});
dataOnprem.addDependency(eksOnprem);

// ---------------------------------------------------------------------------
// Phase 4: Data Stacks – US-W (MSK + MSK Connect)
// ---------------------------------------------------------------------------

const dataUsw = new DataUswStack(app, 'DataUswStack', {
  env: envWest,
  vpc: uswVpc.drVpc.vpc,
  dataSubnets: uswVpc.drVpc.dataSubnets,
  privateSubnets: uswVpc.drVpc.privateSubnets,
});
dataUsw.addDependency(eksUsw);

// ---------------------------------------------------------------------------
// Phase 4: Aurora DSQL Multi-Region
// ---------------------------------------------------------------------------

const auroraDsql = new AuroraDsqlStack(app, 'AuroraDsqlStack', {
  env: envWest,
  linkedRegion: Config.drRegion,
});
auroraDsql.addDependency(dataUsw);

// ---------------------------------------------------------------------------
// Phase 4: Data Stacks – US-E (MSK + MSK Connect)
// ---------------------------------------------------------------------------

const dataUse = new DataUseStack(app, 'DataUseStack', {
  env: envEast,
  vpc: useVpc.drVpc.vpc,
  dataSubnets: useVpc.drVpc.dataSubnets,
  privateSubnets: useVpc.drVpc.privateSubnets,
});
dataUse.addDependency(eksUse);

// ---------------------------------------------------------------------------
// Phase 5: Replication – MSK Replicator (US-W -> US-E)
// ---------------------------------------------------------------------------

const mskReplicator = new MskReplicatorStack(app, 'MskReplicatorStack', {
  env: envWest,
  crossRegionReferences: true,
  sourceMskClusterArn: dataUsw.mskClusterArn,
  targetMskClusterArn: dataUse.mskClusterArn,
});
mskReplicator.addDependency(dataUsw);
mskReplicator.addDependency(dataUse);

app.synth();
