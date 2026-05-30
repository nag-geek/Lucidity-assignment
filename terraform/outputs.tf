output "ecr_repository_url" {
  description = "ECR repository URL for the hello-world image"
  value       = aws_ecr_repository.hello_world.repository_url
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}
