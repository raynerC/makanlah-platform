output "state_bucket" {
  description = "S3 bucket holding all terraform remote state"
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "ci_readonly_plan_role_arn" {
  description = "Role assumed by GitHub Actions for plan/read-only jobs (any ref)"
  value       = aws_iam_role.ci_readonly_plan.arn
}

output "ci_deploy_role_arn" {
  description = "Role assumed by GitHub Actions for deploys (main/tags/environments only)"
  value       = aws_iam_role.ci_deploy.arn
}
