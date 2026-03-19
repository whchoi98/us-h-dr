apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${cluster_name}
  region: ${region}
  version: "${eks_version}"
vpc:
  id: "${vpc_id}"
  subnets:
    private:
      ${az_a}:
        id: "${private_subnet_a}"
      ${az_b}:
        id: "${private_subnet_b}"
managedNodeGroups:
  - name: ng-main
    instanceType: ${node_type}
    desiredCapacity: ${node_count}
    minSize: ${node_count}
    maxSize: ${node_count}
    volumeSize: 100
    volumeType: gp3
    amiFamily: AmazonLinux2023
    iam:
      instanceRoleARN: "${node_role_arn}"
addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver
  - name: aws-efs-csi-driver
  - name: eks-pod-identity-agent
  - name: amazon-cloudwatch-observability
  - name: aws-load-balancer-controller
    version: v3.1.0
  - name: karpenter
    version: v1.9.0
