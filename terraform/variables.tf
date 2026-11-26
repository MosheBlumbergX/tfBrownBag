# --- Input variables ---------------------------------------------------------
# Brownbag topic 4: "Terraform variables".
#
# Precedence, lowest to highest:
#   default here  <  terraform.tfvars  <  TF_VAR_<name> env var  <  -var on the CLI
#
# scripts/lib.sh sets TF_VAR_region / TF_VAR_name from .env, so the same config
# runs in another region without editing a single file.

variable "name" {
  description = "Name prefix for every resource (VPCs, EKS cluster, Confluent Cloud environment, ...)."
  type        = string
  default     = "tf-brownbag"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.name))
    error_message = "name must be 3-25 lowercase letters, digits or dashes and start with a letter."
  }
}

variable "region" {
  description = "AWS region. The Confluent Cloud gateway, and Enterprise cluster all live in the same region."
  type        = string
  default     = "eu-central-1"
}

# --- Networking --------------------------------------------------------------

variable "hub_vpc_cidr" {
  description = "Hub VPC: holds the Confluent Cloud PrivateLink endpoint and the Route53 private zone. No workloads."
  type        = string
  default     = "10.40.0.0/16"
}

variable "spoke_vpc_cidr" {
  description = "Spoke VPC: holds EKS, the clients that talk to Confluent Cloud. Reaches the hub over the Transit Gateway."
  type        = string
  default     = "10.42.0.0/16"
}

# --- EKS ---------------------------------------------------------------------

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.34"
}

variable "node_instance_type" {
  description = "Worker size. The nodes only host test pods, so this is generous."
  type        = string
  default     = "m5.xlarge"
}

variable "eks_admin_sso_permission_set" {
  description = "Name of the IAM Identity Center permission set whose role gets EKS cluster admin when you run Terraform from a laptop."
  type        = string
  default     = "nonprod-administrator"
}

variable "ci_role_name" {
  description = "IAM role GitHub Actions assumes (created by ../bootstrap). It also gets EKS cluster admin."
  type        = string
  default     = "tfBrownBag-github-actions"
}

variable "node_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

# --- Confluent Cloud ---------------------------------------------------------

variable "ccloud_environment_name" {
  description = "Confluent Cloud environment name. Defaults to var.name."
  type        = string
  default     = null
}

# --- Tagging -----------------------------------------------------------------
# Mandatory tags. Kept as individual variables (not one map) so a missing value
# is a plan-time error rather than a surprise on the invoice.

variable "owner_email" {
  description = "owner_email tag."
  type        = string
  default     = "mblumberg@confluent.io"
}

variable "owner_name" {
  description = "owner_name tag."
  type        = string
  default     = "mblumberg"
}

variable "cflt_service" {
  description = "cflt_service tag."
  type        = string
  default     = "CSTA"
}

variable "cflt_managed_by" {
  description = "cflt_managed_by tag."
  type        = string
  default     = "mblumberg"
}

variable "cflt_managed_id" {
  description = "cflt_managed_id tag: the project or demo this infrastructure belongs to."
  type        = string
  default     = "tf-brownbag"
}

variable "cflt_keep_until" {
  description = "cflt_keep_until tag: YYYY-MM-DD, at most ~30 days out. Resources past this date get reaped."
  type        = string
  default     = "2026-12-03"

  validation {
    condition     = can(formatdate("YYYY-MM-DD", "${var.cflt_keep_until}T00:00:00Z"))
    error_message = "cflt_keep_until must be a YYYY-MM-DD date."
  }
}

variable "extra_tags" {
  description = "Any additional AWS tags, merged on top of the mandatory ones."
  type        = map(string)
  default     = {}
}
