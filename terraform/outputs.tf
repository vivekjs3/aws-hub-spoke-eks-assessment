################################################################################
# outputs.tf — Key outputs for integration and pipeline reference
################################################################################

# ─── Hub VPC ──────────────────────────────────────────────────────────────────

output "hub_vpc_id" {
  description = "ID of the Hub (public) VPC"
  value       = module.hub_vpc.vpc_id
}

output "hub_vpc_cidr" {
  description = "CIDR block of the Hub VPC"
  value       = module.hub_vpc.vpc_cidr_block
}

output "hub_public_subnets" {
  description = "List of public subnet IDs in the Hub VPC"
  value       = module.hub_vpc.public_subnets
}

# ─── Spoke VPC ────────────────────────────────────────────────────────────────

output "spoke_vpc_id" {
  description = "ID of the Spoke (private / EKS) VPC"
  value       = module.spoke_vpc.vpc_id
}

output "spoke_vpc_cidr" {
  description = "CIDR block of the Spoke VPC"
  value       = module.spoke_vpc.vpc_cidr_block
}

output "spoke_private_subnets" {
  description = "List of private subnet IDs in the Spoke VPC"
  value       = module.spoke_vpc.private_subnets
}

# ─── Transit Gateway ──────────────────────────────────────────────────────────

output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.main.id
}

output "tgw_hub_attachment_id" {
  description = "TGW attachment ID for the Hub VPC"
  value       = aws_ec2_transit_gateway_vpc_attachment.hub.id
}

output "tgw_spoke_attachment_id" {
  description = "TGW attachment ID for the Spoke VPC"
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke.id
}

# ─── ALB ──────────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  description = "DNS name of the Hub ALB (user-facing entry point)"
  value       = aws_lb.hub.dns_name
}

output "alb_arn" {
  description = "ARN of the Hub ALB"
  value       = aws_lb.hub.arn
}

output "alb_zone_id" {
  description = "Route53 Zone ID of the Hub ALB (for alias records)"
  value       = aws_lb.hub.zone_id
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

output "eks_cluster_id" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS Kubernetes API server"
  value       = module.eks.cluster_endpoint
  sensitive   = false
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "eks_cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster (used for IRSA)"
  value       = module.eks.cluster_oidc_issuer_url
}

output "eks_node_security_group_id" {
  description = "Security Group ID attached to EKS managed nodes"
  value       = module.eks.node_security_group_id
}

output "eks_configure_kubectl" {
  description = "Run this command to configure kubectl for the cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# ─── Account ──────────────────────────────────────────────────────────────────

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS Region"
  value       = var.aws_region
}
