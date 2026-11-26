# --- Terraform block ---------------------------------------------------------
# Brownbag topic 1: "Terraform basics".
#
# Three things live here and nowhere else:
#   1. which Terraform CLI versions this code is known to work with
#   2. which providers it needs, where they come from, and which versions
#   3. how each provider is configured
#
# `terraform init` reads this block, downloads the providers into .terraform/
# and writes the exact versions it picked into .terraform.lock.hcl (commit that
# file: it is what makes a plan reproducible for the next person and for CI).

terraform {
  required_version = ">= 1.6"

  required_providers {
    # The AWS provider: VPCs, Transit Gateway, EKS, IAM, Route53.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # The Confluent provider: environments, clusters, service accounts, API
    # keys, PrivateLink gateways/access points. Same workflow as AWS, same
    # state file, same plan/apply loop.
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.50"
    }
  }

  # Brownbag topic 3: "Terraform state".
  # State is local by default (terraform.tfstate next to this file) and it
  # CONTAINS SECRETS (kubeconfig data, provider credentials). For anything shared, move it
  # to a remote, encrypted, locked backend: see backend.tf.example.
}

# --- Providers ---------------------------------------------------------------

provider "aws" {
  region = var.region

  # Every AWS resource this provider creates gets these tags, with no per
  # resource boilerplate. Resources AWS launches on our behalf (EC2 instances
  # behind a managed node group, EBS volumes behind a PVC) do NOT inherit them,
  # so those get the tags passed explicitly: see eks.tf.
  default_tags {
    tags = local.tags
  }
}

# Credentials come from the environment:
#   CONFLUENT_CLOUD_API_KEY / CONFLUENT_CLOUD_API_SECRET
# scripts/lib.sh exports them from .env. Never put them in a .tf file.
provider "confluent" {}
