################################################################################
# variables.tf — Hub-Spoke EKS Assessment
# All configurable parameters are centralised here.
################################################################################

variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Unique project identifier used as a prefix for all resource names"
  type        = string
  default     = "hubspoke"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "prod"
}

# ─── CIDR blocks ──────────────────────────────────────────────────────────────

variable "hub_vpc_cidr" {
  description = "CIDR block for the Hub (public) VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "hub_public_subnets" {
  description = "List of public subnet CIDRs in the Hub VPC"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "spoke_vpc_cidr" {
  description = "CIDR block for the Spoke (private / EKS) VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "spoke_private_subnets" {
  description = "List of private subnet CIDRs in the Spoke VPC"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
}

variable "availability_zones" {
  description = "List of Availability Zones to use for subnets"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
}

# ─── EKS ──────────────────────────────────────────────────────────────────────

variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "hubspoke-eks-cluster"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_min_size" {
  description = "Minimum number of nodes in the EKS node group"
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of nodes in the EKS node group"
  type        = number
  default     = 6
}

variable "eks_node_desired_size" {
  description = "Desired number of nodes in the EKS node group"
  type        = number
  default     = 3
}

variable "eks_node_disk_size" {
  description = "EBS disk size (GiB) for EKS worker nodes"
  type        = number
  default     = 50
}

# ─── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "hub-spoke-eks-assessment"
    ManagedBy   = "Terraform"
    Environment = "prod"
    Owner       = "platform-team"
    CostCenter  = "engineering"
  }
}
