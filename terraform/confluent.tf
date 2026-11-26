# --- Confluent Cloud: environment, cluster, identities -----------------------
# The point of the session: Confluent Cloud is just another provider. Same
# resources/data-sources/outputs, same plan and apply, same state file as the
# AWS side, and references across the two (privatelink.tf) are what tie the
# whole thing together.

resource "confluent_environment" "demo" {
  display_name = coalesce(var.ccloud_environment_name, var.name)

  # Required by the provider. ESSENTIALS is the free tier.
  stream_governance {
    package = "ESSENTIALS"
  }
}

# --- Kafka cluster -----------------------------------------------------------
# Enterprise: serverless, elastic, and private-only. It is reachable through
# the environment's ingress access point - the one we built in privatelink.tf -
# so it needs no networking configuration of its own.

resource "confluent_kafka_cluster" "demo" {
  display_name = var.name
  availability = "LOW"
  cloud        = "AWS"
  region       = var.region

  enterprise {}

  environment {
    id = confluent_environment.demo.id
  }

  # Nothing in the arguments above refers to the access point, so Terraform
  # cannot infer the ordering. depends_on states it explicitly: the cluster
  # must be created after the access point or it gets no private endpoint.
  depends_on = [confluent_access_point.hub]
}

locals {
  # A cluster can be published through several access points. Pick the endpoint
  # served by ours.
  cluster_endpoint = one([
    for e in confluent_kafka_cluster.demo.endpoints : e
    if e.access_point_id == confluent_access_point.hub.id
  ])
}
