output "cluster_id" {
  description = "ID for EKS control plane."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

output "cluster_issuer" {
  description = "OIDC Issuer for EKS."
  value       = module.eks.cluster_oidc_issuer_url
}

output "cluster_ca" {
  description = "Cluster CA."
  value       = base64decode(module.eks.cluster_certificate_authority_data)
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane."
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region."
  value       = var.region
}

output "aws_kms_key" {
  description = "AWS KMS id"
  value       = aws_kms_key.vault.id
}