locals {
  cluster_name = "${var.name_prefix}-eks"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  public_subnets  = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i, az in var.availability_zones : cidrsubnet(var.vpc_cidr, 4, i + 4)]

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = true
  single_nat_gateway = true # one shared NAT instead of one per AZ — cheaper, acceptable for a course project

  # Tags the LB Controller and cluster autoscaler look for to auto-discover subnets.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # This account blocks iam:CreateOpenIDConnectProvider, so IRSA is not usable —
  # controllers (LB Controller, ESO, ExternalDNS, EBS CSI) get AWS permissions
  # via the shared node role instead (wired up in infra/iam).
  enable_irsa = false

  # This account also blocks iam:TagRole — an empty map avoids the module
  # trying to tag any IAM role it creates, which would fail the apply.
  iam_role_tags = {}

  # Skip creating a customer-managed KMS key for secrets encryption — KMS
  # permissions haven't been verified in this account, and it's not a
  # requirement for the project. Revisit if we confirm kms:CreateKey works.
  cluster_encryption_config = {}

  eks_managed_node_group_defaults = {
    iam_role_use_name_prefix = true # avoids fixed-name collisions on apply retries
    iam_role_tags            = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]

      min_size     = var.node_group_size.min
      max_size     = var.node_group_size.max
      desired_size = var.node_group_size.desired
    }
  }
}
