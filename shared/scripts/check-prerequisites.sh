#!/bin/bash
set -e
echo "Checking prerequisites..."

for cmd in aws eksctl kubectl helm jq python3 docker; do
  if command -v $cmd &>/dev/null; then
    echo "  [OK] $cmd: $(command -v $cmd)"
  else
    echo "  [MISSING] $cmd"
    exit 1
  fi
done

echo ""
echo "AWS CLI version: $(aws --version)"
echo "eksctl version: $(eksctl version)"
echo "kubectl version: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "helm version: $(helm version --short)"
echo "All prerequisites satisfied."
