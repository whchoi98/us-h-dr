import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { Construct } from 'constructs';

export interface CloudFrontAlbStackProps extends cdk.StackProps {
  vpc: ec2.IVpc;
  publicSubnets: ec2.ISubnet[];
  regionLabel: string;
}

export class CloudFrontAlbStack extends cdk.Stack {
  public readonly alb: elbv2.ApplicationLoadBalancer;
  public readonly albSecurityGroup: ec2.SecurityGroup;
  public readonly targetGroup: elbv2.ApplicationTargetGroup;
  public readonly distribution: cloudfront.Distribution;

  constructor(scope: Construct, id: string, props: CloudFrontAlbStackProps) {
    super(scope, id, props);

    const customSecret = cdk.Fn.select(0, cdk.Fn.split('-', cdk.Fn.select(2, cdk.Fn.split('/', this.stackId))));

    // -------------------------------------------------------------------------
    // ALB Security Group – allow traffic from CloudFront prefix list
    // -------------------------------------------------------------------------

    this.albSecurityGroup = new ec2.SecurityGroup(this, 'AlbSg', {
      vpc: props.vpc,
      description: `ALB SG for ${props.regionLabel} - allows CloudFront prefix list`,
      allowAllOutbound: true,
    });

    // CloudFront managed prefix list (com.amazonaws.global.cloudfront.origin-facing)
    const cfPrefixListId = ec2.Peer.prefixList(
      cdk.Fn.importValue('CloudFrontPrefixListId') || 'pl-3b927c52' // fallback for us-east-1
    );

    // Allow HTTP from CloudFront prefix list
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP from CloudFront'
    );

    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS from CloudFront'
    );

    // -------------------------------------------------------------------------
    // Application Load Balancer
    // -------------------------------------------------------------------------

    this.alb = new elbv2.ApplicationLoadBalancer(this, 'ALB', {
      vpc: props.vpc,
      internetFacing: true,
      securityGroup: this.albSecurityGroup,
      vpcSubnets: { subnets: props.publicSubnets },
      loadBalancerName: `dr-lab-${props.regionLabel.toLowerCase()}-alb`,
    });

    // -------------------------------------------------------------------------
    // Target Group for EKS (IP type)
    // -------------------------------------------------------------------------

    this.targetGroup = new elbv2.ApplicationTargetGroup(this, 'EksTargetGroup', {
      vpc: props.vpc,
      targetType: elbv2.TargetType.IP,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      healthCheck: {
        path: '/healthz',
        interval: cdk.Duration.seconds(30),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      targetGroupName: `dr-lab-${props.regionLabel.toLowerCase()}-eks-tg`,
    });

    // -------------------------------------------------------------------------
    // HTTP Listener – default 403 action
    // -------------------------------------------------------------------------

    const listener = this.alb.addListener('HttpListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultAction: elbv2.ListenerAction.fixedResponse(403, {
        contentType: 'text/plain',
        messageBody: 'Forbidden',
      }),
    });

    // Forward if X-Custom-Secret header matches
    listener.addAction('ForwardToEks', {
      priority: 1,
      conditions: [
        elbv2.ListenerCondition.httpHeader('X-Custom-Secret', [customSecret]),
      ],
      action: elbv2.ListenerAction.forward([this.targetGroup]),
    });

    // -------------------------------------------------------------------------
    // CloudFront Distribution
    // -------------------------------------------------------------------------

    this.distribution = new cloudfront.Distribution(this, 'Distribution', {
      defaultBehavior: {
        origin: new origins.HttpOrigin(this.alb.loadBalancerDnsName, {
          protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
          customHeaders: {
            'X-Custom-Secret': customSecret,
          },
        }),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
      },
      comment: `DR Lab ${props.regionLabel} distribution`,
    });

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, 'AlbDnsName', {
      value: this.alb.loadBalancerDnsName,
      description: `ALB DNS name for ${props.regionLabel}`,
    });

    new cdk.CfnOutput(this, 'DistributionDomainName', {
      value: this.distribution.distributionDomainName,
      description: `CloudFront domain for ${props.regionLabel}`,
    });

    new cdk.CfnOutput(this, 'DistributionId', {
      value: this.distribution.distributionId,
    });

    cdk.Tags.of(this).add('Component', 'cloudfront-alb');
    cdk.Tags.of(this).add('Region', props.regionLabel);
  }
}
