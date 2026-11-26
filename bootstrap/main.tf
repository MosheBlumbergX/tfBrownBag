# --- GitHub Actions -> AWS, with no static keys -------------------------------
# Applied once, by hand, with its own local state. It lives apart from
# ../terraform because CI needs this role in order to run that configuration:
# the role cannot be created by the pipeline that depends on it.

data "aws_caller_identity" "current" {}

locals {
  oidc_url = "token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_url}"
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only this repo (by its immutable ID, see variables.tf), and only the
    # contexts the workflow uses:
    #   pull_request            the plan job on a PR
    #   ref:refs/heads/main     the plan job after a merge
    #   environment:production  the apply job (behind required reviewers)
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values = [
        "repo:${var.github_oidc_subject_prefix}:pull_request",
        "repo:${var.github_oidc_subject_prefix}:ref:refs/heads/main",
        "repo:${var.github_oidc_subject_prefix}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name                 = var.role_name
  description          = "GitHub Actions for ${var.github_repo}. project=${var.cflt_managed_id} keep_until=${var.cflt_keep_until}"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

# The demo builds VPCs, a Transit Gateway, EKS and IAM roles, so it needs broad
# rights. Fine for a short-lived demo role; scope it down for anything real.
resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
