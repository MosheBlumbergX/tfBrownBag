output "role_arn" {
  description = "Put this in the repository secret AWS_ROLE_ARN."
  value       = aws_iam_role.github_actions.arn
}

output "state_bucket" {
  description = "S3 bucket for the main stack's state (see terraform/backend.tf)."
  value       = aws_s3_bucket.state.id
}
