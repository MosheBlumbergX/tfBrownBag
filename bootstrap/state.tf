# --- Remote state bucket -----------------------------------------------------
# Holds the state of ../terraform, shared by your laptop and CI. It lives here
# (not in ../terraform) because a configuration cannot store its state in a
# bucket it has not created yet.
#
# State contains secrets in plain text, so: encrypted, versioned, private, and
# TLS-only. S3 native locking (use_lockfile) replaces the old DynamoDB table.

variable "state_bucket_name" {
  description = "Globally unique name of the S3 bucket that holds the main stack's state."
  type        = string
  default     = "tfbrownbag-tfstate-mblumberg"
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # Demo bucket: let `terraform destroy` remove it even though it holds state
  # versions. Never do this for a real state bucket.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
