output "state_bucket_name" {
  description = "Name of S3 bucket"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "github_actions_role_arn" {
  description = "ARN of IAM Role for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}