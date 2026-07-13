output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "oidc_issuer" {
  description = "Issuer URL without the https:// prefix, as IAM trust conditions want it"
  value       = trimprefix(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://")
}
