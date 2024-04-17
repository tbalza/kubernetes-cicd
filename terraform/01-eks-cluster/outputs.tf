output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "The endpoint for the EKS cluster API. Required to configure kubectl."
}

output "eks" {
  value       = module.eks
  description = "The EKS module itself."
}

output "cluster_certificate_authority_data" {
  value       = module.eks.cluster_certificate_authority_data
  description = "The certificate authority data for the EKS cluster."
}

output "cluster_name" {
  value       = module.eks.cluster_name
  description = "The name of the EKS cluster."
}

output "region" {
  value       = local.region
  description = "The AWS region where the EKS cluster is deployed."
}

output "name" {
  value       = local.name
  description = "Cluster name."
}

output "access_entries" {
  value       = module.eks.access_entries
  description = "Security group entries that allow access to the EKS cluster."
}

output "access_policy_associations" {
  value       = module.eks.access_policy_associations
  description = "IAM policy associations required for EKS access."
}