#!/bin/bash
# Source this file to set EKS environment variables
export AWS_REGION="${1:-us-west-2}"
export CLUSTER_NAME="${2:-onprem-eks}"
echo "Setting up EKS environment for cluster: $CLUSTER_NAME in $AWS_REGION"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl get nodes
