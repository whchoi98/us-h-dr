export const Config = {
  environment: 'dr-lab',
  project: 'us-h-dr',
  primaryRegion: 'us-west-2',
  drRegion: 'us-east-1',
  witnessRegion: 'us-east-2',

  vpcs: {
    onprem: {
      name: 'Onprem',
      cidr: '10.0.0.0/16',
      publicSubnets: ['10.0.0.0/24', '10.0.1.0/24'],
      privateSubnets: ['10.0.16.0/20', '10.0.32.0/20'],
      dataSubnets: ['10.0.48.0/23', '10.0.50.0/23'],
      tgwSubnets: ['10.0.252.0/24', '10.0.253.0/24'],
    },
    uswCenter: {
      name: 'US-W-CENTER',
      cidr: '10.1.0.0/16',
      publicSubnets: ['10.1.0.0/24', '10.1.1.0/24'],
      privateSubnets: ['10.1.16.0/20', '10.1.32.0/20'],
      dataSubnets: ['10.1.48.0/23', '10.1.50.0/23'],
      tgwSubnets: ['10.1.252.0/24', '10.1.253.0/24'],
    },
    useCenter: {
      name: 'US-E-CENTER',
      cidr: '10.2.0.0/16',
      publicSubnets: ['10.2.0.0/24', '10.2.1.0/24'],
      privateSubnets: ['10.2.16.0/20', '10.2.32.0/20'],
      dataSubnets: ['10.2.48.0/23', '10.2.50.0/23'],
      tgwSubnets: ['10.2.252.0/24', '10.2.253.0/24'],
    },
  },

  eks: { version: '1.33', nodeType: 't4g.2xlarge', nodeCount: 8 },
  msk: { instanceType: 'kafka.m7g.xlarge', brokerCount: 4 },
  db: { instanceType: 'r7g.large' },
  kafka: { instanceType: 'm7g.xlarge', brokerCount: 4 },
  vscode: { instanceType: 'm7g.xlarge' },
};
