variable "region" {
  description = "AWS region for the provider. IAM is global, this only sets the API endpoint."
  type        = string
  default     = "eu-central-1"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the role, as owner/name."
  type        = string
  default     = "MosheBlumbergX/tfBrownBag"
}

variable "github_oidc_subject_prefix" {
  description = "How GitHub names this repo in its OIDC token. New repos use the immutable form owner@ownerID/repo@repoID, so renaming or recreating the repo cannot inherit the trust. Get it with: gh api repos/<owner>/<repo>/actions/oidc/customization/sub -q .sub_claim_prefix"
  type        = string
  default     = "MosheBlumbergX@23198209/tfBrownBag@1472996975"
}

variable "role_name" {
  description = "Name of the IAM role GitHub Actions assumes."
  type        = string
  default     = "tfBrownBag-github-actions"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if the account already has one (an account can have only one per URL)."
  type        = bool
  default     = true
}

variable "owner_email" {
  type    = string
  default = "mblumberg@confluent.io"
}

variable "owner_name" {
  type    = string
  default = "mblumberg"
}

variable "cflt_service" {
  type    = string
  default = "CSTA"
}

variable "cflt_managed_by" {
  type    = string
  default = "mblumberg"
}

variable "cflt_managed_id" {
  type    = string
  default = "tf-brownbag"
}

variable "cflt_keep_until" {
  description = "cflt_keep_until tag: YYYY-MM-DD, at most ~30 days out."
  type        = string
  default     = "2026-12-03"
}
