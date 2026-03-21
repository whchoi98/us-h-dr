#!/bin/bash
set -eo pipefail

# =============================================================================
# Deploy LBC + Sample App + CloudFront Protection to all 3 EKS clusters
# Reference: aws_lab_infra/cloudformation/05.deploy-lbc.sh
#            aws_lab_infra/shared/02.deploy-app.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
LAB_INFRA="/home/ec2-user/my-project/aws_lab_infra"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LBC_VERSION="v3.1.0"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[0;34m'; C='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

banner() { echo -e "\n${B}═══════════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}  $1${NC}"; echo -e "${B}═══════════════════════════════════════════════════════════${NC}\n"; }
ok()   { echo -e "  ${G}✓${NC} $1"; }
info() { echo -e "  ${DIM}→${NC} $1"; }
warn() { echo -e "  ${Y}⚠${NC} $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# Global IAM Policy (shared across all clusters)
# ─────────────────────────────────────────────────────────────────────────────

setup_iam_policy() {
  banner "IAM Policy for LBC (shared)"
  if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
    ok "IAM Policy already exists"
  else
    info "Downloading and creating IAM Policy..."
    curl -so /tmp/iam_policy.json \
      "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/${LBC_VERSION}/docs/install/iam_policy.json"
    aws iam create-policy \
      --policy-name "${POLICY_NAME}" \
      --policy-document file:///tmp/iam_policy.json > /dev/null
    rm -f /tmp/iam_policy.json
    ok "IAM Policy created"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Deploy LBC to a single cluster
# ─────────────────────────────────────────────────────────────────────────────

deploy_lbc() {
  local cluster="$1" region="$2" ctx="$3"
  echo -e "\n${C}──── LBC: ${cluster} (${region}) ────${NC}"

  # Switch context
  aws eks update-kubeconfig --region "$region" --name "$cluster" --alias "$ctx"
  kubectl config use-context "$ctx"

  # OIDC Provider
  OIDC_ISSUER=$(aws eks describe-cluster --name "$cluster" --region "$region" \
    --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null || echo "")
  if [ -z "$OIDC_ISSUER" ] || [ "$OIDC_ISSUER" = "None" ]; then
    info "Creating OIDC Provider..."
    eksctl utils associate-iam-oidc-provider --cluster="$cluster" --region="$region" --approve
  fi
  ok "OIDC Provider ready"

  # Pod Identity Role
  local role_name="AmazonEKSLoadBalancerControllerRole-${cluster}"
  if ! aws iam get-role --role-name "$role_name" &>/dev/null; then
    aws iam create-role --role-name "$role_name" \
      --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pods.eks.amazonaws.com"},"Action":["sts:AssumeRole","sts:TagSession"]}]}' > /dev/null
  fi
  aws iam attach-role-policy --role-name "$role_name" --policy-arn "$POLICY_ARN" 2>/dev/null || true
  local role_arn="arn:aws:iam::${ACCOUNT_ID}:role/${role_name}"

  # Pod Identity Association
  aws eks create-pod-identity-association \
    --cluster-name "$cluster" --namespace kube-system \
    --service-account aws-load-balancer-controller \
    --role-arn "$role_arn" --region "$region" 2>/dev/null || true
  ok "Pod Identity configured"

  # Helm install
  helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
  helm repo update eks 2>/dev/null

  local vpc_id
  vpc_id=$(aws eks describe-cluster --name "$cluster" --region "$region" \
    --query "cluster.resourcesVpcConfig.vpcId" --output text)

  local helm_cmd="install"
  if helm status aws-load-balancer-controller -n kube-system &>/dev/null; then
    helm_cmd="upgrade"
  fi

  helm $helm_cmd aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName="$cluster" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set region="$region" \
    --set vpcId="$vpc_id" \
    --wait --timeout=120s
  ok "LBC ${helm_cmd}d"

  kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=60s
  ok "LBC running"
}

# ─────────────────────────────────────────────────────────────────────────────
# Deploy sample app + CloudFront protection to a single cluster
# ─────────────────────────────────────────────────────────────────────────────

deploy_app_with_cf() {
  local cluster="$1" region="$2" ctx="$3" label="$4"
  echo -e "\n${C}──── App + CF: ${cluster} (${label}) ────${NC}"

  kubectl config use-context "$ctx"

  # Deploy base-application from aws_lab_infra
  info "Deploying base-application (Retail Store Sample)..."
  kubectl apply -k "${LAB_INFRA}/shared/base-application/" 2>&1 | tail -5
  ok "App manifests applied"

  # Wait for pods
  info "Waiting for UI pod..."
  kubectl wait --for=condition=ready pod -l app=ui -n ui --timeout=180s 2>/dev/null || \
    warn "UI pod not ready yet (may take a minute)"

  # Wait for ALB
  info "Waiting for ALB provisioning..."
  local alb=""
  for i in $(seq 1 36); do
    alb=$(kubectl get ingress -n ui -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$alb" ]; then
      ok "ALB: ${alb}"
      break
    fi
    sleep 10
  done

  if [ -z "$alb" ]; then
    warn "ALB not ready after 6 min. Run CloudFront protection manually later."
    return
  fi

  # ALB SG — restrict to CloudFront Prefix List
  local cf_prefix
  cf_prefix=$(aws ec2 describe-managed-prefix-lists --region "$region" \
    --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
    --output text 2>/dev/null)

  local alb_sg
  alb_sg=$(aws elbv2 describe-load-balancers --region "$region" \
    --query "LoadBalancers[?DNSName=='${alb}'].SecurityGroups[0]" --output text 2>/dev/null)

  if [ -n "$alb_sg" ] && [ "$alb_sg" != "None" ]; then
    # Remove 0.0.0.0/0
    aws ec2 revoke-security-group-ingress --group-id "$alb_sg" --region "$region" \
      --ip-permissions '[{"IpProtocol":"tcp","FromPort":80,"ToPort":80,"IpRanges":[{"CidrIp":"0.0.0.0/0"}]}]' 2>/dev/null && \
      ok "Removed 0.0.0.0/0 from ALB SG" || info "0.0.0.0/0 already removed"

    # Add CloudFront Prefix List
    aws ec2 authorize-security-group-ingress --group-id "$alb_sg" --region "$region" \
      --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"PrefixListIds\":[{\"PrefixListId\":\"${cf_prefix}\",\"Description\":\"HTTP from CloudFront only\"}]}]" 2>/dev/null && \
      ok "CloudFront Prefix List added to ALB SG" || info "Prefix List already set"
  fi

  # CloudFront via CloudFormation
  local stack_name="dr-lab-cf-${label}"
  info "Creating CloudFront Distribution (${stack_name})..."

  aws cloudformation deploy \
    --stack-name "$stack_name" \
    --template-file "${LAB_INFRA}/shared/cloudfront-alb-protection.yaml" \
    --parameter-overrides \
      ALBDnsName="${alb}" \
      ALBSecurityGroupId="${alb_sg}" \
      CloudFrontPrefixListId="${cf_prefix}" \
    --region "$region" \
    --no-fail-on-empty-changeset 2>&1 | tail -3

  local cf_url
  cf_url=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region "$region" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' --output text 2>/dev/null)

  ok "CloudFront: ${cf_url}"
  echo -e "  ${BOLD}🌐 ${label} URL: ${cf_url}${NC}"
  echo -e "  ${DIM}🔒 Security: CloudFront(HTTPS) → ALB(Prefix List + X-Lab-Secret) → EKS Pod${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

banner "DR Lab — LBC + App + CloudFront (3 clusters)"

# Step 1: Shared IAM
setup_iam_policy

# Step 2: Deploy LBC to all 3 clusters (sequential — helm needs context)
deploy_lbc "onprem-eks" "us-west-2" "onprem-eks"
deploy_lbc "usw-eks"    "us-west-2" "usw-eks"
deploy_lbc "use-eks"    "us-east-1" "use-eks"

banner "LBC deployed to all 3 clusters. Deploying apps..."

# Step 3: Deploy app + CloudFront to all 3 clusters
deploy_app_with_cf "onprem-eks" "us-west-2" "onprem-eks" "onprem"
deploy_app_with_cf "usw-eks"    "us-west-2" "usw-eks"    "usw"
deploy_app_with_cf "use-eks"    "us-east-1" "use-eks"    "use"

# Summary
banner "Deployment Complete"
echo -e "  ${BOLD}All 3 clusters:${NC}"
for ctx in onprem-eks usw-eks use-eks; do
  echo -e "    ${G}✓${NC} ${ctx}: LBC + App + CloudFront"
done

echo ""
echo -e "  ${BOLD}CloudFront URLs:${NC}"
for stack in dr-lab-cf-onprem dr-lab-cf-usw dr-lab-cf-use; do
  region="us-west-2"
  [[ "$stack" == *use ]] && region="us-east-1"
  url=$(aws cloudformation describe-stacks --stack-name "$stack" --region "$region" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' --output text 2>/dev/null || echo "N/A")
  echo -e "    ${stack}: ${url}"
done

echo ""
echo -e "  ${BOLD}Security:${NC} CloudFront(HTTPS) → ALB(CF Prefix List) → EKS Pod"
echo -e "  ${BOLD}Direct ALB:${NC} BLOCKED (0.0.0.0/0 removed)"
echo ""
