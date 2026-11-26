#!/usr/bin/env bash
# Terraform: VPCs, Transit Gateway, EKS, PrivateLink, Route53, and the
# Confluent Cloud environment and Enterprise cluster.
#
# Brownbag topics 6 and 7: "terraform plan" and "terraform apply".
#   make plan   -> writes a saved plan to terraform/tfplan and shows it
#   make apply  -> applies exactly that plan, no surprises in between
#   make infra  -> the two in one go (what `make up` runs)
source "$(dirname "$0")/lib.sh"
require terraform aws kubectl

aws sts get-caller-identity >/dev/null 2>&1 ||
  { echo "No usable AWS credentials. Run 'aws sso login' first." >&2; exit 1; }

log "terraform init"
terraform -chdir="$TF_DIR" init -upgrade -input=false >/dev/null

if [[ -f "$TF_DIR/tfplan" ]]; then
  log "applying the saved plan (terraform/tfplan)"
  terraform -chdir="$TF_DIR" apply -input=false tfplan
  rm -f "$TF_DIR/tfplan"
else
  log "terraform apply (~20 min: EKS and the PrivateLink chain are the slow parts)"
  terraform -chdir="$TF_DIR" apply -input=false -auto-approve
fi

log "writing kubeconfig to $KUBECONFIG"
aws eks update-kubeconfig \
  --name "$(tf_out eks_cluster_name)" \
  --region "$(tf_out region)" \
  --kubeconfig "$KUBECONFIG" >/dev/null

kubectl get nodes
