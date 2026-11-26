# --- Data contracts in git ---------------------------------------------------
# Every file in schemas/ is a schema. The file name is the Schema Registry
# subject, using the topic-name strategy: orders-value.avsc is the value schema
# for topic "orders". Edit the file in a PR and the plan shows the schema diff.
#
# Compatibility is pinned to BACKWARD per subject, in code. A change that would
# break existing consumers (a new required field, a removed field without a
# default) is rejected at plan time: the provider checks the new schema against
# the registered version, so the PR fails before anyone reads it.
#
# Schema Registry is a public endpoint, so this also works from a GitHub runner.

locals {
  schemas = {
    for f in fileset("${path.module}/schemas", "*.avsc") :
    trimsuffix(f, ".avsc") => "${path.module}/schemas/${f}"
  }
}

resource "confluent_schema" "this" {
  for_each = local.schemas

  subject_name = each.key
  format       = "AVRO"
  schema       = file(each.value)

  # Remove the subject for good on destroy, not just soft-delete it.
  hard_delete = true

  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.demo.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.demo.rest_endpoint

  credentials {
    key    = confluent_api_key.catalog.id
    secret = confluent_api_key.catalog.secret
  }
}

resource "confluent_subject_config" "this" {
  for_each = local.schemas

  subject_name        = confluent_schema.this[each.key].subject_name
  compatibility_level = "BACKWARD"

  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.demo.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.demo.rest_endpoint

  credentials {
    key    = confluent_api_key.catalog.id
    secret = confluent_api_key.catalog.secret
  }
}
