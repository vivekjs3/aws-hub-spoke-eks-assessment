################################################################################
# eks.tf — EKS Cluster in Spoke VPC (private subnets only)
# Uses official terraform-aws-modules/eks for best practices.
# Defense-in-depth: Node SG allows ingress ONLY from Hub VPC CIDR.
################################################################################

################################################################################
# EKS CLUSTER
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name    = var.eks_cluster_name
  cluster_version = var.eks_cluster_version

  # Deploy control plane in Spoke VPC private subnets
  vpc_id                   = module.spoke_vpc.vpc_id
  subnet_ids               = module.spoke_vpc.private_subnets
  control_plane_subnet_ids = module.spoke_vpc.private_subnets

  # Endpoint security — private only (no public endpoint for production)
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true # Set false in production; keep true for assessment

  # Cluster-level logging (best practice)
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # Cluster add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true # Ensure VPC CNI is ready before nodes join
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  # OIDC provider for IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Managed Node Groups
  eks_managed_node_groups = {
    main = {
      name           = "${var.project_name}-nodes"
      instance_types = var.eks_node_instance_types

      min_size     = var.eks_node_min_size
      max_size     = var.eks_node_max_size
      desired_size = var.eks_node_desired_size

      disk_size = var.eks_node_disk_size

      # Use AL2 for broad compatibility
      ami_type = "AL2_x86_64"

      # Launch template customisation
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.eks_node_disk_size
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 125
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Node labels for workload scheduling
      labels = {
        role        = "application"
        Environment = var.environment
      }

      # Taints (optional — remove for assessment)
      # taints = {}

      tags = merge(var.tags, {
        Name = "${var.project_name}-node-group"
      })
    }
  }

  # ─── Cluster Security Group additional rules ───────────────────────────────
  cluster_security_group_additional_rules = {
    ingress_from_hub_vpc = {
      description = "Allow inbound from Hub VPC CIDR (via TGW) — defense-in-depth"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [var.hub_vpc_cidr]
    }
  }

  # ─── Node Security Group additional rules ─────────────────────────────────
  # CRITICAL: Only allow ingress from Hub VPC CIDR — no open internet access
  node_security_group_additional_rules = {
    ingress_from_hub_vpc_all = {
      description = "Allow ALL traffic from Hub VPC CIDR (TGW sourced) — defense-in-depth"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = [var.hub_vpc_cidr]
    }
    ingress_self_all = {
      description = "Allow node-to-node communication within cluster"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description = "Allow all outbound (for ECR, S3 VPC endpoints, etc.)"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # Port 15017 required for Istio webhook
    ingress_istio_webhook = {
      description                   = "Allow control plane → Istio webhook"
      protocol                      = "tcp"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
    # Port 8080 / 8443 for Istio health checks
    ingress_istio_healthz = {
      description = "Allow Istio readiness checks from Hub VPC"
      protocol    = "tcp"
      from_port   = 8080
      to_port     = 8080
      type        = "ingress"
      cidr_blocks = [var.hub_vpc_cidr]
    }
  }

  tags = merge(var.tags, {
    Name = var.eks_cluster_name
  })
}

################################################################################
# IRSA — EBS CSI Driver
################################################################################

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${var.project_name}-ebs-csi-irsa"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

################################################################################
# VPC ENDPOINTS — Allow Spoke VPC nodes to reach AWS services privately
# (No NAT Gateway in Spoke — endpoints provide private connectivity)
################################################################################

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.spoke_vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.spoke_vpc.private_subnets
  security_group_ids  = [module.eks.node_security_group_id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.project_name}-ecr-api-endpoint" })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.spoke_vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.spoke_vpc.private_subnets
  security_group_ids  = [module.eks.node_security_group_id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.project_name}-ecr-dkr-endpoint" })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.spoke_vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.spoke_vpc.private_route_table_ids

  tags = merge(var.tags, { Name = "${var.project_name}-s3-endpoint" })
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = module.spoke_vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.spoke_vpc.private_subnets
  security_group_ids  = [module.eks.node_security_group_id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.project_name}-sts-endpoint" })
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.spoke_vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.spoke_vpc.private_subnets
  security_group_ids  = [module.eks.node_security_group_id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.project_name}-ssm-endpoint" })
}
