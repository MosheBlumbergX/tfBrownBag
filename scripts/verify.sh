#!/usr/bin/env bash
# Proof that the private path works end to end, from inside the spoke VPC:
#
#   pod in EKS -> Route53 private zone -> hub VPC endpoint ENIs -> TGW -> PrivateLink
#
# Runs a throwaway pod that resolves the cluster's bootstrap host and opens a
# TCP connection to it. No Kafka client and no credentials are needed: the point
# is the network path, which is what Terraform built.
source "$(dirname "$0")/lib.sh"
require kubectl terraform

HOST_PORT="$(tf_out ccloud_bootstrap | sed -E 's#^[A-Za-z_]+://##')"
HOST="${HOST_PORT%%:*}"
PORT="${HOST_PORT##*:}"
HUB_CIDR="$(tf_out hub_vpc_cidr)"

log "from a pod in the spoke VPC: resolve and connect to $HOST_PORT"
echo "  (answers must be private addresses inside the hub range $HUB_CIDR)"
echo

kubectl run ccloud-verify --rm -i --restart=Never --quiet \
  --image=busybox:1.37 --command -- sh -c "
    nslookup $HOST | awk '/^Address/ && !/#/ {print \"  resolves to \" \$2}'
    if nc -z -w 5 $HOST $PORT; then
      echo '  tcp/$PORT: open'
    else
      echo '  tcp/$PORT: FAILED'; exit 1
    fi"
