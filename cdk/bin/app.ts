#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Config } from '../lib/config';
import { OnpremVpcStack } from '../lib/onprem-vpc-stack';
import { UswCenterVpcStack } from '../lib/usw-center-vpc-stack';
import { UseCenterVpcStack } from '../lib/use-center-vpc-stack';

const app = new cdk.App();

const envWest = { account: process.env.CDK_DEFAULT_ACCOUNT, region: Config.primaryRegion };
const envEast = { account: process.env.CDK_DEFAULT_ACCOUNT, region: Config.drRegion };

// ---------------------------------------------------------------------------
// Phase 1: VPC Stacks
// ---------------------------------------------------------------------------

const onpremVpc = new OnpremVpcStack(app, 'OnpremVpcStack', { env: envWest });
const uswVpc = new UswCenterVpcStack(app, 'UswCenterVpcStack', { env: envWest });
const useVpc = new UseCenterVpcStack(app, 'UseCenterVpcStack', { env: envEast });

// Stacks for subsequent phases will be added as they are implemented
// See: docs/superpowers/specs/2026-03-19-multi-region-dr-infra-design.md Section 10.2

app.synth();
