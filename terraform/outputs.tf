# --- Outputs -----------------------------------------------------------------
# Brownbag topic 5: "Terraform output".
#
# Outputs are the published interface of this configuration. Scripts and people
# read values from here rather than hard-coding them:
#
#   terraform output                      # all non-sensitive values
#   terraform output -raw ccloud_cluster_id
#   terraform output -json | jq .
#
# Marking an output `sensitive` hides it from the CLI and from CI logs. It does
# NOT encrypt it: the value is still plain text in the state file. That is the
# single best argument for a remote encrypted backend (backend.tf.example).

output "region" {
  description = "AWS region everything was deployed into."
  value       = var.region
}

output "eks_cluster_name" {
  description = "EKS cluster name (used by `aws eks update-kubeconfig`)."
  value       = module.eks.cluster_name
}

output "transit_gateway_id" {
  description = "Transit Gateway joining the spoke (EKS) and hub (PrivateLink) VPCs."
  value       = aws_ec2_transit_gateway.this.id
}

output "hub_vpc_cidr" {
  description = "Hub VPC range. Confluent hostnames must resolve to addresses inside it."
  value       = var.hub_vpc_cidr
}

output "ccloud_access_point_dns_domain" {
  description = "DNS domain Confluent publishes our private endpoints under; the Route53 private zone mirrors it."
  value       = local.ccloud_dns_domain
}

output "ccloud_environment_id" {
  description = "Confluent Cloud environment ID (env-...)."
  value       = confluent_environment.demo.id
}

output "ccloud_cluster_id" {
  description = "Enterprise Kafka cluster ID (lkc-...)."
  value       = confluent_kafka_cluster.demo.id
}

output "ccloud_bootstrap" {
  description = "Private bootstrap endpoint, reachable from the spoke VPC over the TGW + PrivateLink."
  value       = local.cluster_endpoint.bootstrap_endpoint
}

output "ccloud_rest_endpoint" {
  description = "Private Admin REST endpoint (PrivateLink only, so Terraform cannot manage topics here)."
  value       = local.cluster_endpoint.rest_endpoint
}

output "ccloud_console_url" {
  description = "Deep link to this environment in the Confluent Cloud Console."
  value       = "https://confluent.cloud/environments/${confluent_environment.demo.id}/clusters/${confluent_kafka_cluster.demo.id}"
}
