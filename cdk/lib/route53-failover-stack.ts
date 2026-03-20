import * as cdk from 'aws-cdk-lib';
import * as route53 from 'aws-cdk-lib/aws-route53';
import { Construct } from 'constructs';
import { Config } from './config';

export interface Route53FailoverStackProps extends cdk.StackProps {
  /** CloudFront domain for primary (US-W) */
  primaryCloudfrontDomain: string;
  /** CloudFront domain for DR (US-E) */
  drCloudfrontDomain: string;
  /** Domain name for the hosted zone */
  domainName: string;
}

/**
 * Route 53 failover routing stack.
 *
 * Creates a private hosted zone with health checks and failover records
 * for the primary (us-west-2) and DR (us-east-1) CloudFront distributions.
 */
export class Route53FailoverStack extends cdk.Stack {
  public readonly hostedZone: route53.HostedZone;

  constructor(scope: Construct, id: string, props: Route53FailoverStackProps) {
    super(scope, id, props);

    // -------------------------------------------------------------------------
    // Hosted Zone
    // -------------------------------------------------------------------------

    this.hostedZone = new route53.HostedZone(this, 'HostedZone', {
      zoneName: props.domainName,
      comment: `DR Lab failover zone for ${props.domainName}`,
    });

    // -------------------------------------------------------------------------
    // Health Check – Primary (US-W)
    // -------------------------------------------------------------------------

    const primaryHealthCheck = new route53.CfnHealthCheck(this, 'PrimaryHealthCheck', {
      healthCheckConfig: {
        type: 'HTTPS',
        fullyQualifiedDomainName: props.primaryCloudfrontDomain,
        port: 443,
        resourcePath: '/',
        requestInterval: 30,
        failureThreshold: 3,
        enableSni: true,
      },
      healthCheckTags: [
        { key: 'Name', value: `dr-lab-primary-health-check` },
      ],
    });

    // -------------------------------------------------------------------------
    // Health Check – DR (US-E)
    // -------------------------------------------------------------------------

    const drHealthCheck = new route53.CfnHealthCheck(this, 'DrHealthCheck', {
      healthCheckConfig: {
        type: 'HTTPS',
        fullyQualifiedDomainName: props.drCloudfrontDomain,
        port: 443,
        resourcePath: '/',
        requestInterval: 30,
        failureThreshold: 3,
        enableSni: true,
      },
      healthCheckTags: [
        { key: 'Name', value: `dr-lab-dr-health-check` },
      ],
    });

    // -------------------------------------------------------------------------
    // Failover Records
    // -------------------------------------------------------------------------

    // Primary failover record
    new route53.CfnRecordSet(this, 'PrimaryFailoverRecord', {
      hostedZoneId: this.hostedZone.hostedZoneId,
      name: `app.${props.domainName}`,
      type: 'CNAME',
      ttl: '60',
      setIdentifier: 'primary',
      failover: 'PRIMARY',
      healthCheckId: primaryHealthCheck.ref,
      resourceRecords: [props.primaryCloudfrontDomain],
    });

    // DR failover record
    new route53.CfnRecordSet(this, 'DrFailoverRecord', {
      hostedZoneId: this.hostedZone.hostedZoneId,
      name: `app.${props.domainName}`,
      type: 'CNAME',
      ttl: '60',
      setIdentifier: 'secondary',
      failover: 'SECONDARY',
      healthCheckId: drHealthCheck.ref,
      resourceRecords: [props.drCloudfrontDomain],
    });

    // -------------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------------

    new cdk.CfnOutput(this, 'HostedZoneId', {
      value: this.hostedZone.hostedZoneId,
      description: 'Hosted zone ID',
    });

    new cdk.CfnOutput(this, 'PrimaryHealthCheckId', {
      value: primaryHealthCheck.ref,
      description: 'Primary health check ID',
    });

    new cdk.CfnOutput(this, 'DrHealthCheckId', {
      value: drHealthCheck.ref,
      description: 'DR health check ID',
    });

    new cdk.CfnOutput(this, 'FailoverFqdn', {
      value: `app.${props.domainName}`,
      description: 'Failover FQDN',
    });

    cdk.Tags.of(this).add('Component', 'route53-failover');
  }
}
