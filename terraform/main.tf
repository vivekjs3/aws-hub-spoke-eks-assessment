################################################################################
# main.tf — Hub VPC · Spoke VPC · Transit Gateway · Route Tables
# Uses official terraform-aws-modules for VPC (industry best practice).
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }

  # ── Remote state backend — S3 + DynamoDB locking ─────────────────────────
  # Bucket and DynamoDB table are provisioned by terraform/backend.tf (bootstrap).
  # Values are injected at init-time via -backend-config flags or the ADO pipeline.
  # Run `terraform init -reconfigure -backend-config=backend.hcl` to switch backends.
  backend "s3" {
    bucket         = "hubspoke-tfstate-ap-southeast-1"   # set via -backend-config in CI
    key            = "hub-spoke/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "hubspoke-tfstate-lock"
    # Optional: use a KMS key ARN for customer-managed encryption
    # kms_key_id   = "arn:aws:kms:ap-southeast-1:ACCOUNT_ID:key/KEY_ID"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# ─── Data Sources ─────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

################################################################################
# HUB VPC — Public subnets + Internet Gateway
################################################################################

module "hub_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.project_name}-hub-vpc"
  cidr = var.hub_vpc_cidr

  azs            = var.availability_zones
  public_subnets = var.hub_public_subnets

  # Hub VPC has no private subnets — it is purely the public-facing tier
  private_subnets = []

  enable_nat_gateway   = false # No NAT needed; Hub is public-only
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags for ALB auto-discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
    Tier                     = "public"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-hub-vpc"
    Role = "hub"
  })
}

################################################################################
# SPOKE VPC — Private subnets ONLY (no IGW, no NAT — EKS workloads)
################################################################################

module "spoke_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.project_name}-spoke-vpc"
  cidr = var.spoke_vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.spoke_private_subnets

  # Spoke VPC intentionally has NO public subnets, NO IGW, NO NAT
  public_subnets = []

  enable_nat_gateway   = false
  enable_vpn_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags for EKS internal load balancer discovery
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"                       = "1"
    "kubernetes.io/cluster/${var.eks_cluster_name}"         = "shared"
    Tier                                                    = "private"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-spoke-vpc"
    Role = "spoke"
  })
}

################################################################################
# TRANSIT GATEWAY — Central network hub
################################################################################

resource "aws_ec2_transit_gateway" "main" {
  description                     = "${var.project_name} Transit Gateway — Hub-Spoke"
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable" # We manage route tables explicitly
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw"
  })
}

# ─── TGW Attachment: Hub VPC ──────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_vpc_attachment" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = module.hub_vpc.vpc_id
  subnet_ids         = module.hub_vpc.public_subnets # attach in public subnets

  dns_support                                     = "enable"
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw-attachment-hub"
    Side = "hub"
  })
}

# ─── TGW Attachment: Spoke VPC ────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = module.spoke_vpc.vpc_id
  subnet_ids         = module.spoke_vpc.private_subnets

  dns_support                                     = "enable"
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw-attachment-spoke"
    Side = "spoke"
  })
}

################################################################################
# TGW ROUTE TABLES — Explicit routing (no default tables used)
################################################################################

# ─── Hub Route Table ─────────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_route_table" "hub" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw-rt-hub"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

# Hub route table propagates Spoke routes so Hub knows how to reach Spoke CIDR
resource "aws_ec2_transit_gateway_route_table_propagation" "hub_learns_spoke" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.hub.id
}

# ─── Spoke Route Table ────────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-tgw-rt-spoke"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

# Spoke route table propagates Hub routes so Spoke knows how to reach Hub CIDR
resource "aws_ec2_transit_gateway_route_table_propagation" "spoke_learns_hub" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
}

################################################################################
# VPC ROUTE TABLE ENTRIES — Point to TGW for cross-VPC traffic
################################################################################

# Hub public subnets → Spoke CIDR via TGW
resource "aws_route" "hub_to_spoke_via_tgw" {
  count = length(module.hub_vpc.public_route_table_ids)

  route_table_id         = module.hub_vpc.public_route_table_ids[count.index]
  destination_cidr_block = var.spoke_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.hub]
}

# Spoke private subnets → Hub CIDR via TGW
resource "aws_route" "spoke_to_hub_via_tgw" {
  count = length(module.spoke_vpc.private_route_table_ids)

  route_table_id         = module.spoke_vpc.private_route_table_ids[count.index]
  destination_cidr_block = var.hub_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

# Spoke private subnets → default route via TGW (for return traffic / egress via Hub)
# Note: This is optional — only needed if the Hub has egress infrastructure (NAT, etc.)
# resource "aws_route" "spoke_default_via_tgw" {
#   count                  = length(module.spoke_vpc.private_route_table_ids)
#   route_table_id         = module.spoke_vpc.private_route_table_ids[count.index]
#   destination_cidr_block = "0.0.0.0/0"
#   transit_gateway_id     = aws_ec2_transit_gateway.main.id
#   depends_on             = [aws_ec2_transit_gateway_vpc_attachment.spoke]
# }
