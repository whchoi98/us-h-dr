#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Config } from '../lib/config';

const app = new cdk.App();

const envWest = { account: process.env.CDK_DEFAULT_ACCOUNT, region: Config.primaryRegion };
const envEast = { account: process.env.CDK_DEFAULT_ACCOUNT, region: Config.drRegion };

// Stacks will be added as they are implemented
// See: docs/superpowers/specs/2026-03-19-multi-region-dr-infra-design.md Section 10.2

app.synth();
