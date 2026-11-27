#!/bin/bash
set -eo pipefail

# =============================================================================
# Deploy LBC + Sample App + CloudFront Protection to all 3 EKS clusters
# Reference: aws_lab_infra/cloudformation/05.deploy-lbc.sh
#            aws_lab_infra/shared/02.deploy-app.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"
LAB_INFRA="/home/ec2-user/my-project/infra/aws_lab_infra"
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

  # CloudFront origin-facing prefix list — required BEFORE the Ingress is applied
  # so the ALB is never created with the LBC default (0.0.0.0/0).
  local cf_prefix
  cf_prefix=$(aws ec2 describe-managed-prefix-lists --region "$region" \
    --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
    --output text 2>/dev/null)
  if [[ ! "$cf_prefix" =~ ^pl-[0-9a-f]+$ ]]; then
    echo -e "  ${R}✗${NC} CloudFront prefix list not found in ${region} — refusing to deploy a public ALB"
    return 1
  fi

  # Deploy base-application from aws_lab_infra through a hardening overlay.
  # The ALB SG is owned by the AWS Load Balancer Controller: any CLI edit to it is
  # reverted on the next resync (~10h), so restrictions MUST be Ingress annotations.
  #   - security-group-prefix-lists: allow CloudFront only (no 0.0.0.0/0 default)
  #   - /actuator(/*) answered with 404 at the ALB (inserted before "/")
  # ALB health checks and Prometheus scraping hit the pod directly, so they are unaffected.
  info "Deploying base-application (Retail Store Sample) with ALB hardening overlay..."
  local overlay base_rel
  overlay=$(mktemp -d)
  base_rel=$(realpath --relative-to="$overlay" "${LAB_INFRA}/shared/base-application")
  cat > "${overlay}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ${base_rel}
patches:
  - target:
      group: networking.k8s.io
      version: v1
      kind: Ingress
      name: ui-ingress
      namespace: ui
    patch: |-
      - op: add
        path: /metadata/annotations/alb.ingress.kubernetes.io~1security-group-prefix-lists
        value: ${cf_prefix}
      - op: add
        path: /metadata/annotations/alb.ingress.kubernetes.io~1actions.block-actuator
        value: '{"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","statusCode":"404","messageBody":"Not Found"}}'
      - op: add
        path: /spec/rules/0/http/paths/0
        value:
          path: /actuator
          pathType: Prefix
          backend:
            service:
              name: block-actuator
              port:
                name: use-annotation
EOF

  # Fail closed: never apply an Ingress that lacks the restriction.
  # Render into a variable first — `kubectl kustomize | grep -q` can SIGPIPE under pipefail.
  local rendered
  if ! rendered=$(kubectl kustomize "$overlay") || \
     ! grep -q "security-group-prefix-lists: ${cf_prefix}" <<<"$rendered" || \
     ! grep -q "name: block-actuator" <<<"$rendered"; then
    rm -rf "$overlay"
    echo -e "  ${R}✗${NC} Hardening overlay did not render — aborting"
    return 1
  fi
  kubectl apply -k "$overlay" 2>&1 | tail -5
  rm -rf "$overlay"
  ok "App manifests applied (Ingress: CloudFront prefix list ${cf_prefix}, /actuator blocked)"

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

  # Verify (read-only) that LBC applied the restriction — no 0.0.0.0/0 on any ALB SG
  local alb_sgs open_sgs
  alb_sgs=$(aws elbv2 describe-load-balancers --region "$region" \
    --query "LoadBalancers[?DNSName=='${alb}'].SecurityGroups[]" --output text 2>/dev/null)
  if [ -n "$alb_sgs" ]; then
    # shellcheck disable=SC2086  # word splitting intended: list of SG IDs
    open_sgs=$(aws ec2 describe-security-groups --region "$region" --group-ids $alb_sgs \
      --query "SecurityGroups[?IpPermissions[?IpRanges[?CidrIp=='0.0.0.0/0']]].GroupId" --output text 2>/dev/null)
    if [ -n "$open_sgs" ]; then
      echo -e "  ${R}✗${NC} ALB SG still open to 0.0.0.0/0 (${open_sgs}) — check LBC logs before exposing via CloudFront"
      return 1
    fi
    ok "ALB SG restricted to CloudFront prefix list (managed by LBC)"
  fi

  # CloudFront via CloudFormation (distribution only — SG rules are owned by LBC)
  local stack_name="dr-lab-cf-${label}"
  info "Creating CloudFront Distribution (${stack_name})..."

  aws cloudformation deploy \
    --stack-name "$stack_name" \
    --template-file "${DEMO_DIR}/cfn/cloudfront-ui.yaml" \
    --parameter-overrides \
      ALBDnsName="${alb}" \
    --region "$region" \
    --no-fail-on-empty-changeset 2>&1 | tail -3

  local cf_url
  cf_url=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region "$region" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' --output text 2>/dev/null)

  ok "CloudFront: ${cf_url}"
  echo -e "  ${BOLD}🌐 ${label} URL: ${cf_url}${NC}"
  echo -e "  ${DIM}🔒 Security: CloudFront(HTTPS) → ALB(CloudFront Prefix List via LBC, /actuator → 404) → EKS Pod${NC}"
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
