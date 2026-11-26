#!/usr/bin/env bash
# Check the target AWS account and region BEFORE spending twenty minutes on an
# apply that cannot finish.
#
# This exists because the first run of this demo died halfway through: the
# account had a service control policy denying eks:CreateCluster,
# ec2:CreateNatGateway and ec2:CreateVpcEndpoint, and its Transit Gateway
# quota was already exceeded. None of that shows up in `terraform plan` -
# a plan asks "what would change", not "am I allowed to change it".
#
#   make preflight
source "$(dirname "$0")/lib.sh"
require aws jq curl

REGION="${TF_VAR_region:-${DEMO_REGION:-us-east-1}}"
fail=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=1; }
meh()  { printf '  \033[33m?\033[0m %s\n' "$*"; }

log "AWS identity"
if ! ident="$(aws sts get-caller-identity --output json 2>/dev/null)"; then
  bad "no usable AWS credentials - run 'aws sso login' (and set AWS_PROFILE in .env)"
  exit 1
fi
ok "$(jq -r '.Arn' <<<"$ident")"
echo "    account $(jq -r '.Account' <<<"$ident")  region $REGION"

# --- Quotas ------------------------------------------------------------------
# used vs limit, for the four things this demo is most likely to run out of.
quota() { # label used quota-code service-code need
  local label=$1 used=$2 code=$3 svc=$4 need=$5
  local limit
  limit="$(aws service-quotas get-service-quota --region "$REGION" \
    --service-code "$svc" --quota-code "$code" --query 'Quota.Value' --output text 2>/dev/null)"
  if [[ -z "$limit" || "$limit" == "None" ]]; then
    meh "$label: $used in use, quota unknown"
    return
  fi
  limit="${limit%.*}"
  if ((used + need > limit)); then
    bad "$label: $used of $limit in use, demo needs $need more"
  else
    ok "$label: $used of $limit in use, demo needs $need more"
  fi
}

log "quota headroom in $REGION"
quota "VPCs" "$(aws ec2 describe-vpcs --region "$REGION" --query 'length(Vpcs)' --output text)" \
  L-F678F1CE vpc 2
quota "Elastic IPs" "$(aws ec2 describe-addresses --region "$REGION" --query 'length(Addresses)' --output text)" \
  L-0263D0A3 ec2 1
quota "Transit Gateways" "$(aws ec2 describe-transit-gateways --region "$REGION" --query "length(TransitGateways[?State!='deleted'])" --output text)" \
  L-A2478D36 ec2 1
quota "Internet Gateways" "$(aws ec2 describe-internet-gateways --region "$REGION" --query 'length(InternetGateways)' --output text)" \
  L-A4707A72 vpc 1

# --- Permissions -------------------------------------------------------------
# These have to be real probes. "The account already has 40 NAT gateways" is
# NOT evidence that you may create one: a service control policy added later
# denies the create while every existing resource keeps running. That exact
# false positive is what sent the first run of this demo into a wall.
log "permissions (service control policies bite here)"

classify() { # label output
  case "$2" in
    *DryRunOperation*) ok "$1 allowed" ;;
    *UnauthorizedOperation* | *AccessDenied* | *"explicit deny"*) bad "$1 DENIED - service control policy" ;;
    *) meh "$1 unclear: $(head -c 100 <<<"$2" | tr -d '\n')" ;;
  esac
}

# EC2 DryRun checks authorization and returns DryRunOperation if you would
# have been allowed. It validates the resource arguments first, though, so
# these need a real VPC and subnet to point at - any will do, we never create
# anything.
probe_vpc="$(aws ec2 describe-vpcs --region "$REGION" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)"
probe_subnet="$(aws ec2 describe-subnets --region "$REGION" --query 'Subnets[0].SubnetId' --output text 2>/dev/null)"

classify "ec2:CreateTransitGateway" \
  "$(aws ec2 create-transit-gateway --dry-run --region "$REGION" 2>&1 || true)"

if [[ -n "$probe_vpc" && "$probe_vpc" != "None" ]]; then
  classify "ec2:CreateVpcEndpoint" \
    "$(aws ec2 create-vpc-endpoint --dry-run --region "$REGION" \
      --vpc-id "$probe_vpc" --service-name "com.amazonaws.$REGION.s3" 2>&1 || true)"
else
  meh "ec2:CreateVpcEndpoint untested - no existing VPC in $REGION to probe against"
fi

if [[ -n "$probe_subnet" && "$probe_subnet" != "None" ]]; then
  classify "ec2:CreateNatGateway" \
    "$(aws ec2 create-nat-gateway --dry-run --region "$REGION" --subnet-id "$probe_subnet" 2>&1 || true)"
else
  meh "ec2:CreateNatGateway untested - no existing subnet in $REGION to probe against"
fi

# EKS has no DryRun. Authorization is evaluated before the arguments, so we
# call CreateCluster with an IAM role that cannot exist: denied means denied,
# and anything else means we got past the policy and died on validation.
eks_probe="$(aws eks create-cluster --region "$REGION" \
  --name tf-brownbag-preflight-probe \
  --role-arn "arn:aws:iam::$(jq -r '.Account' <<<"$ident"):role/tf-brownbag-preflight-probe-does-not-exist" \
  --resources-vpc-config subnetIds=subnet-0000000000000000a,subnet-0000000000000000b 2>&1 || true)"
case "$eks_probe" in
  *AccessDenied* | *"explicit deny"*) bad "eks:CreateCluster DENIED - service control policy" ;;
  *) ok "eks:CreateCluster allowed" ;;
esac

# --- Confluent Cloud ---------------------------------------------------------
log "Confluent Cloud credentials"
if org="$(ccloud_api GET /org/v2/organizations | jq -r '.data[0].display_name // empty')" && [[ -n "$org" ]]; then
  ok "authenticated against org \"$org\""
else
  bad "CONFLUENT_CLOUD_API_KEY / _SECRET rejected - needs a Cloud resource management key"
fi

echo
if ((fail)); then
  warn "preflight failed - fix the above before 'make up', or pick another account/region"
  exit 1
fi
log "preflight passed - 'make up' should go the distance"
