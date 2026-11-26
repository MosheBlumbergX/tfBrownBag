#!/usr/bin/env bash
# Brownbag topic 8: "terraform destroy".
#
# Everything here is owned by Terraform, so teardown is one command: Terraform
# walks the dependency graph in reverse (cluster, access point, endpoint, EKS,
# TGW, VPCs...).
source "$(dirname "$0")/lib.sh"
require terraform

log "terraform destroy (~15 min)"
# Confluent tag bindings are removed asynchronously, so the first destroy can
# fail with 409 Conflict deleting the tags. Wait a minute and go again.
if ! terraform -chdir="$TF_DIR" destroy -input=false -auto-approve; then
  warn "destroy failed (likely 409 on tags); retrying in 60s"
  sleep 60
  terraform -chdir="$TF_DIR" destroy -input=false -auto-approve
fi

rm -f "$KUBECONFIG"
log "done - nothing left behind"
