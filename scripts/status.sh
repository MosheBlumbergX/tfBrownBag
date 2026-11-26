#!/usr/bin/env bash
# Where everything stands: what Terraform built, and the way in.
source "$(dirname "$0")/lib.sh"
require terraform kubectl

log "Terraform outputs"
terraform -chdir="$TF_DIR" output
echo

log "EKS nodes"
kubectl get nodes
echo

echo "Console: $(tf_out ccloud_console_url)"
echo "Next:    make verify   (prove the private path from inside the VPC)"
