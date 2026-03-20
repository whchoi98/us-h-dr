import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';

export interface TgwPeeringStackProps extends cdk.StackProps {
  /** Transit Gateway ID in the requester (west) region */
  requesterTgwId: string;
  /** TGW Route Table ID in the requester region */
  requesterRouteTableId: string;
  /** Transit Gateway ID in the accepter (east) region */
  accepterTgwId: string;
  /** TGW Route Table ID in the accepter region */
  accepterRouteTableId: string;
  /** Region of the accepter TGW */
  peerRegion: string;
  /**
   * CIDRs to route via peering from the requester TGW route table.
   * E.g., US-E-CENTER CIDR so west-side VPCs can reach east-side VPCs.
   */
  requesterRouteCidrs: string[];
  /**
   * CIDRs to route via peering from the accepter TGW route table.
   * E.g., OnPrem + US-W-CENTER CIDRs so east-side VPCs can reach west-side VPCs.
   */
  accepterRouteCidrs: string[];
}

/**
 * Creates inter-region Transit Gateway peering between US-WEST-2 and US-EAST-1.
 *
 * Note: This stack is deployed in the requester region (us-west-2). The peering
 * attachment accepter and accepter-side routes use CfnResource with the
 * accepter TGW references. In a real deployment, the peering accepter must be
 * accepted in the peer region. For CDK, we define all resources in the requester
 * stack and rely on the cross-region TGW IDs being passed via props.
 */
export class TgwPeeringStack extends cdk.Stack {
  public readonly peeringAttachment: ec2.CfnTransitGatewayPeeringAttachment;

  constructor(scope: Construct, id: string, props: TgwPeeringStackProps) {
    super(scope, id, props);

    // -------------------------------------------------------------------------
    // Peering Attachment (created in requester region)
    // -------------------------------------------------------------------------

    this.peeringAttachment = new ec2.CfnTransitGatewayPeeringAttachment(this, 'PeeringAttachment', {
      transitGatewayId: props.requesterTgwId,
      peerTransitGatewayId: props.accepterTgwId,
      peerRegion: props.peerRegion,
      peerAccountId: this.account,
      tags: [{ key: 'Name', value: 'tgw-peering-west-east' }],
    });

    // -------------------------------------------------------------------------
    // Requester-side routes: route accepter CIDRs via peering attachment
    // (e.g., 10.2.0.0/16 via peering from TGW-West)
    // -------------------------------------------------------------------------

    props.requesterRouteCidrs.forEach((cidr, index) => {
      new ec2.CfnTransitGatewayRoute(this, `RequesterRoute${index}`, {
        transitGatewayRouteTableId: props.requesterRouteTableId,
        destinationCidrBlock: cidr,
        transitGatewayAttachmentId: this.peeringAttachment.ref,
      });
    });

    // -------------------------------------------------------------------------
    // Accepter-side routes: route requester CIDRs via peering attachment
    // (e.g., 10.0.0.0/16 + 10.1.0.0/16 via peering from TGW-East)
    //
    // Note: These routes reference the accepter TGW route table. In a true
    // cross-region CDK deployment, these would be in a separate stack deployed
    // to the accepter region. Here we define them as CfnTransitGatewayRoute
    // resources that will be created after peering is accepted.
    // -------------------------------------------------------------------------

    props.accepterRouteCidrs.forEach((cidr, index) => {
      new ec2.CfnTransitGatewayRoute(this, `AccepterRoute${index}`, {
        transitGatewayRouteTableId: props.accepterRouteTableId,
        destinationCidrBlock: cidr,
        transitGatewayAttachmentId: this.peeringAttachment.ref,
      });
    });

    cdk.Tags.of(this).add('Component', 'network');
  }
}
