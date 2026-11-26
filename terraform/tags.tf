# --- Confluent Cloud tags ----------------------------------------------------
# AWS default_tags does not reach Confluent Cloud, but Confluent has its own
# tags: Stream Catalog tags, managed by confluent_tag and confluent_tag_binding.
#
# They differ from AWS tags in four ways:
#   - a tag is a bare label with no value, so key and value are folded into the
#     name (cflt_keep_until_2026_12_03), underscores only
#   - they live in Schema Registry, so we need an SR endpoint and an SR API key
#   - Schema Registry only exists once the environment has a Kafka cluster
#   - service accounts and API keys cannot be tagged at all (their descriptions
#     carry the project name and keep-until date instead)

locals {
  # The mandatory tags that make sense as bare labels. owner_email is left out:
  # '@' and '.' in a tag name are untested.
  catalog_tags = {
    for k, v in {
      cflt_service    = var.cflt_service
      cflt_managed_by = var.cflt_managed_by
      cflt_managed_id = var.cflt_managed_id
      cflt_keep_until = var.cflt_keep_until
    } : k => lower("${k}_${replace(v, "/[^a-zA-Z0-9_]/", "_")}")
  }

  # What gets tagged: entity_type => entity_name.
  # The environment binding is the tested one. The cluster binding follows the
  # Stream Catalog entity-type docs and has not been applied yet.
  catalog_entities = {
    environment = {
      type = "cf_environment"
      name = "${data.confluent_schema_registry_cluster.demo.id}:${confluent_environment.demo.id}"
    }
    cluster = {
      type = "kafka_logical_cluster"
      name = confluent_kafka_cluster.demo.id
    }
  }

  tag_bindings = {
    for pair in setproduct(keys(local.catalog_tags), keys(local.catalog_entities)) :
    "${pair[0]}/${pair[1]}" => { tag = pair[0], entity = pair[1] }
  }
}

# Schema Registry is created with the first cluster; the provider has no
# standalone resource for it, so read it and wait for the cluster.
data "confluent_schema_registry_cluster" "demo" {
  environment {
    id = confluent_environment.demo.id
  }

  depends_on = [confluent_kafka_cluster.demo]
}

# Tagging needs a Schema Registry API key. This service account exists only for
# that, and its description carries the tags a real tag cannot.
resource "confluent_service_account" "catalog" {
  display_name = "${var.name}-catalog"
  description  = "Manages Stream Catalog tags. project=${var.cflt_managed_id} keep_until=${var.cflt_keep_until}"
}

resource "confluent_role_binding" "catalog" {
  principal   = "User:${confluent_service_account.catalog.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.demo.resource_name
}

resource "confluent_api_key" "catalog" {
  display_name = "${var.name}-catalog"
  description  = "Schema Registry key for tags. project=${var.cflt_managed_id} keep_until=${var.cflt_keep_until}"

  owner {
    id          = confluent_service_account.catalog.id
    api_version = confluent_service_account.catalog.api_version
    kind        = confluent_service_account.catalog.kind
  }

  managed_resource {
    id          = data.confluent_schema_registry_cluster.demo.id
    api_version = data.confluent_schema_registry_cluster.demo.api_version
    kind        = data.confluent_schema_registry_cluster.demo.kind

    environment {
      id = confluent_environment.demo.id
    }
  }

  depends_on = [confluent_role_binding.catalog]
}

resource "confluent_tag" "this" {
  for_each = local.catalog_tags

  name        = each.value
  description = "Mandatory tag ${each.key}"

  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.demo.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.demo.rest_endpoint

  credentials {
    key    = confluent_api_key.catalog.id
    secret = confluent_api_key.catalog.secret
  }
}

# Each binding took about 2 minutes to create in testing; they run in parallel.
resource "confluent_tag_binding" "this" {
  for_each = local.tag_bindings

  tag_name    = confluent_tag.this[each.value.tag].name
  entity_name = local.catalog_entities[each.value.entity].name
  entity_type = local.catalog_entities[each.value.entity].type

  schema_registry_cluster {
    id = data.confluent_schema_registry_cluster.demo.id
  }
  rest_endpoint = data.confluent_schema_registry_cluster.demo.rest_endpoint

  credentials {
    key    = confluent_api_key.catalog.id
    secret = confluent_api_key.catalog.secret
  }
}
