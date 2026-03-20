import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';

export interface TgwEastVpcAttachment {
  name: string;
  vpc: ec2.IVpc;
  subnets: ec2.ISubnet[];
  vpcCidr: string;
}

export interface TgwEastStackProps extends cdk.StackProps {
  tgwName: string;
  amazonSideAsn: number;
  vpcAttachments: TgwEastVpcAttachment[];
}

export class TgwEastStack extends cdk.Stack {
  public readonly tgw: ec2.CfnTransitGateway;
  public readonly routeTable: ec2.CfnTransitGatewayRouteTable;
  public readonly attachmentIds: Record<string, string>;

  constructor(scope: Construct, id: string, props: TgwEastStackProps) {
    super(scope, id, props);

    // -------------------------------------------------------------------------
    // Transit Gateway (US-East-1)
    // -------------------------------------------------------------------------

    this.tgw = new ec2.CfnTransitGateway(this, 'TGW', {
      amazonSideAsn: props.amazonSideAsn,
      autoAcceptSharedAttachments: 'enable',
      defaultRouteTableAssociation: 'disable',
      defaultRouteTablePropagation: 'disable',
      dnsSupport: 'enable',
      vpnEcmpSupport: 'enable',
      tags: [{ key: 'Name', value: props.tgwName }],
    });

    // -------------------------------------------------------------------------
    // Route Table
    // -------------------------------------------------------------------------

    this.routeTable = new ec2.CfnTransitGatewayRouteTable(this, 'TgwRouteTable', {
      transitGatewayId: this.tgw.ref,
      tags: [{ key: 'Name', value: `${props.tgwName}-rt` }],
    });

    // -------------------------------------------------------------------------
    // VPC Attachments, Associations, and Routes
    // -------------------------------------------------------------------------

    this.attachmentIds = {};

    for (const attach of props.vpcAttachments) {
      const attachment = new ec2.CfnTransitGatewayVpcAttachment(this, `Attach-${attach.name}`, {
        transitGatewayId: this.tgw.ref,
        vpcId: attach.vpc.vpcId,
        subnetIds: attach.subnets.map(s => s.subnetId),
        tags: [{ key: 'Name', value: `${props.tgwName}-${attach.name}` }],
      });

      this.attachmentIds[attach.name] = attachment.ref;

      // Associate attachment with route table
      new ec2.CfnTransitGatewayRouteTableAssociation(this, `Assoc-${attach.name}`, {
        transitGatewayAttachmentId: attachment.ref,
        transitGatewayRouteTableId: this.routeTable.ref,
      });

      // Route for each VPC CIDR
      new ec2.CfnTransitGatewayRoute(this, `Route-${attach.name}`, {
        transitGatewayRouteTableId: this.routeTable.ref,
        destinationCidrBlock: attach.vpcCidr,
        transitGatewayAttachmentId: attachment.ref,
      });
    }

    cdk.Tags.of(this).add('Component', 'network');
  }
}
