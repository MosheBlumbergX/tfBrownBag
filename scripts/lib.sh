#!/usr/bin/env bash
# Shared helpers, sourced by every other script. Nothing here talks to a cloud
# API on its own.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$REPO_ROOT/terraform"

# A dedicated kubeconfig, so the demo never touches ~/.kube/config and a stray
# `kubectl delete` cannot hit the wrong cluster.
export KUBECONFIG="$REPO_ROOT/.kubeconfig"

# Load .env, but let the surrounding shell win. `source .env` would do the
# opposite and silently overwrite anything you set on the command line, so
# this one-off override does what it looks like it does:
#
#   AWS_PROFILE=other-account DEMO_REGION=eu-west-1 make preflight
if [[ -f "$REPO_ROOT/.env" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key//[[:space:]]/}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [[ -n "${!key:-}" ]] && continue # already set in the environment: keep it
    export "$key=$value"
  done <"$REPO_ROOT/.env"
  unset line key value
fi

: "${CONFLUENT_CLOUD_API_KEY:?Set CONFLUENT_CLOUD_API_KEY in .env (see .env.example)}"
: "${CONFLUENT_CLOUD_API_SECRET:?Set CONFLUENT_CLOUD_API_SECRET in .env (see .env.example)}"

# .env overrides that Terraform should see. TF_VAR_<name> beats the default in
# variables.tf and loses to an explicit -var on the command line.
[[ -n "${DEMO_NAME:-}" ]] && export TF_VAR_name="$DEMO_NAME"
[[ -n "${DEMO_REGION:-}" ]] && export TF_VAR_region="$DEMO_REGION"

log() { printf '\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*" >&2; }

require() {
  local missing=0
  for bin in "$@"; do
    command -v "$bin" >/dev/null || {
      echo "missing required tool: $bin" >&2
      missing=1
    }
  done
  ((missing == 0)) || exit 1
}

# --- Terraform outputs -------------------------------------------------------
tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
