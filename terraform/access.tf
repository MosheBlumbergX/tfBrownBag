# --- Team access as data -----------------------------------------------------
# teams.yaml lists teams and the topics they may use. Terraform reads it with
# yamldecode and fans it out with for_each: one service account per team, one
# role binding per team and topic. Adding a team is a few lines of YAML, and
# the plan shows exactly the identities and permissions that line creates.
#
# RBAC is control-plane (the public Confluent Cloud API), so unlike the topics
# themselves it works from a laptop or a GitHub runner despite the private
# cluster. A binding on a topic name is valid before the topic exists.

locals {
  teams = yamldecode(file("${path.module}/teams.yaml")).teams

  access_roles = {
    read  = "DeveloperRead"
    write = "DeveloperWrite"
  }

  # Flatten team -> topics into one row per team and topic, keyed "team/topic".
  # Static keys, so for_each is fine (see the for_each note in tgw.tf).
  team_topic_access = merge([
    for team, cfg in local.teams : {
      for t in cfg.topics : "${team}/${t.name}" => {
        team   = team
        topic  = t.name
        access = t.access
      }
    }
  ]...)

  # Readers also need their consumer groups. One binding per team, not per topic.
  reader_teams = toset([for k, v in local.team_topic_access : v.team if v.access == "read"])

  topic_crn_prefix = "${confluent_kafka_cluster.demo.rbac_crn}/kafka=${confluent_kafka_cluster.demo.id}"
}

resource "confluent_service_account" "team" {
  for_each = local.teams

  display_name = "${var.name}-team-${each.key}"
  description  = "Team ${each.key}, from teams.yaml. project=${var.cflt_managed_id} keep_until=${var.cflt_keep_until}"
}

resource "confluent_role_binding" "team_topic" {
  for_each = local.team_topic_access

  principal   = "User:${confluent_service_account.team[each.value.team].id}"
  role_name   = lookup(local.access_roles, each.value.access, "INVALID")
  crn_pattern = "${local.topic_crn_prefix}/topic=${each.value.topic}"

  # A typo in the YAML fails the plan with a readable message, on the PR,
  # before anything is applied.
  lifecycle {
    precondition {
      condition     = contains(keys(local.access_roles), each.value.access)
      error_message = "teams.yaml: ${each.key} has access '${each.value.access}'. Use 'read' or 'write'."
    }
  }
}

resource "confluent_role_binding" "team_group" {
  for_each = local.reader_teams

  principal   = "User:${confluent_service_account.team[each.key].id}"
  role_name   = "DeveloperRead"
  crn_pattern = "${local.topic_crn_prefix}/group=${each.key}-*"
}
