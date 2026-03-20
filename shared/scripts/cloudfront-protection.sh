#!/bin/bash
set -e
ALB_SG_ID=${1:?Usage: $0 <alb-sg-id> <region>}
REGION=${2:-us-west-2}

echo "=== Setting up CloudFront → ALB Protection ==="

# Get CloudFront managed prefix list
CF_PREFIX_LIST=$(aws ec2 describe-managed-prefix-lists \
  --region "$REGION" \
  --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing" \
  --query "PrefixLists[0].PrefixListId" --output text)

echo "CloudFront prefix list: $CF_PREFIX_LIST"

# Verify ALB security group has prefix list rule
EXISTING=$(aws ec2 describe-security-group-rules \
  --region "$REGION" \
  --filters "Name=group-id,Values=$ALB_SG_ID" \
  --query "SecurityGroupRules[?PrefixListId=='$CF_PREFIX_LIST'].SecurityGroupRuleId" \
  --output text)

if [ -n "$EXISTING" ]; then
  echo "CloudFront prefix list already configured in ALB SG."
else
  echo "Adding CloudFront prefix list to ALB SG..."
  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$ALB_SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,PrefixListIds=[{PrefixListId=$CF_PREFIX_LIST}]"
  echo "Added."
fi

echo "=== CloudFront protection configured ==="
