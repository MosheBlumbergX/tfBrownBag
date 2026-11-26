output "role_arn" {
  description = "Put this in the repository secret AWS_ROLE_ARN."
  value       = aws_iam_role.github_actions.arn
}
