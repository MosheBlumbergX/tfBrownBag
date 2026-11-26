#!/usr/bin/env bash
# Brownbag topic 6: "terraform plan".
#
# A plan is a diff between three things: the config, the state file, and what
# the cloud actually looks like right now. Saving it to a file (-out) and
# applying that file is the habit worth teaching: what you reviewed is exactly
# what gets applied, even if someone edits main.tf while you are reading.
source "$(dirname "$0")/lib.sh"
require terraform

terraform -chdir="$TF_DIR" init -input=false >/dev/null
terraform -chdir="$TF_DIR" plan -input=false -out=tfplan

cat <<'EOF'

Saved to terraform/tfplan. Useful next moves:

  terraform -chdir=terraform show -json tfplan | jq '.resource_changes[].change.actions' | sort | uniq -c
  make apply        # applies this exact plan
  rm terraform/tfplan

EOF
