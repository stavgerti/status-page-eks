locals {
  cluster_name = "${var.name_prefix}-eks"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  tags = {
    Owner   = "stav"
    Project = "status-page-eks"
  }

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

# ---------------------------------------------------------------------------
# EKS IAM roles are NOT managed by Terraform in this project.
#
# Why: this account allows iam:CreateRole and iam:AttachRolePolicy, but blocks
# iam:ListRolePolicies and iam:ListAttachedRolePolicies. The AWS provider calls
# both of those every time it reads an aws_iam_role / aws_iam_role_policy_attachment
# (to detect drift in inline and managed policies), so those resources fail on
# create here — verified against provider v5 and v6 alike, and there is no flag
# to turn that read off. A CloudFormation-stack-based workaround was tested and
# worked (Terraform only calls DescribeStacks, which doesn't touch IAM at all),
# but the course admin's guidance was to keep IAM management manual/out-of-band
# in this account rather than let any automation own it — so we're following
# that instead, even though it costs the "one apply, one destroy" story.
#
# The two roles below were created manually via AWS CLI (see repo README or ask
# Stav for the exact commands) with these managed policies:
#   cluster role: AmazonEKSClusterPolicy
#   node role:    AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy,
#                 AmazonEC2ContainerRegistryReadOnly
#
# Consequence for infra/iam: adding the LB Controller/ESO/ExternalDNS/EBS CSI
# policies to the node role will ALSO need to be done manually (the same
# blocked reads apply to aws_iam_role_policy_attachment on this role) — that
# branch should expect the same pattern, not fight it.
# ---------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  tags = {
    Owner   = "stav"
    Project = "status-page-eks"
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Creating the cluster does not by itself grant its creator access to the
  # Kubernetes API — the node role gets an access entry automatically, which is
  # why nodes join fine, but a human running kubectl is rejected with a 401
  # until an access entry exists for them too. This grants the identity that
  # runs Terraform (the `stav` user) cluster-admin through the EKS access-entry
  # API rather than the older aws-auth ConfigMap.
  enable_cluster_creator_admin_permissions = true

  # This account blocks iam:CreateOpenIDConnectProvider, so IRSA is not usable —
  # controllers (LB Controller, ESO, ExternalDNS, EBS CSI) get AWS permissions
  # via the shared node role instead (wired up in infra/iam).
  enable_irsa = false

  # Use the manually-created role above instead of letting the module create
  # an aws_iam_role resource (see the comment above for why).
  create_iam_role = false
  iam_role_arn    = var.cluster_iam_role_arn

  # Only relevant for EKS Auto Mode, which we don't use. Left off so the module
  # doesn't create an extra aws_iam_policy — another IAM resource this account
  # can't tag.
  enable_auto_mode_custom_tags = false

  # Skip creating a customer-managed KMS key for secrets encryption — KMS
  # permissions haven't been verified in this account, and it's not a
  # requirement for the project. Revisit if we confirm kms:CreateKey works.
  cluster_encryption_config = {}

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]

      min_size     = var.node_group_size.min
      max_size     = var.node_group_size.max
      desired_size = var.node_group_size.desired

      # Same story as the cluster role — reuse the manually-created one.
      create_iam_role = false
      iam_role_arn    = var.node_iam_role_arn
    }
  }
}
