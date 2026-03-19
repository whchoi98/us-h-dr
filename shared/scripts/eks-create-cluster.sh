#!/bin/bash
set -e
CONFIG_FILE=${1:?Usage: $0 <eksctl-config.yaml>}
echo "Creating EKS cluster from: $CONFIG_FILE"
eksctl create cluster -f "$CONFIG_FILE"
echo "EKS cluster created successfully."
