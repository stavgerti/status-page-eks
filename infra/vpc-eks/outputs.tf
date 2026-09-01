output "vpc_id" {
  description = "ID of the VPC — needed by infra/data-dns for RDS/ElastiCache subnet groups"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — needed by infra/data-dns for RDS/ElastiCache, and by the node group"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs — needed if anything public-facing is added later"
  value       = module.vpc.public_subnets
}

output "cluster_name" {
  description = "EKS cluster name — needed by platform/bootstrap and app/cicd (kubeconfig, ArgoCD target)"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster CA cert, needed to build a kubeconfig"
  value       = module.eks.cluster_certificate_authority_data
}

output "node_iam_role_arn" {
  description = "IAM role ARN used by the EKS node group — infra/iam attaches the LB Controller/ESO/ExternalDNS/EBS CSI policies here manually (see main.tf), since IRSA isn't available and Terraform can't manage this role's policies in this account"
  value       = var.node_iam_role_arn
}

output "node_security_group_id" {
  description = "Security group attached to the worker nodes. Pod traffic leaves through this SG (VPC CNI gives pods VPC IPs), so this is what RDS/ElastiCache in infra/data-dns must allow inbound from — not the cluster SG."
  value       = module.eks.node_security_group_id
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster's ENIs"
  value       = module.eks.cluster_security_group_id
}
