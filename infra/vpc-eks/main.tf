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
# EKS IAM roles, created through CloudFormation rather than aws_iam_role.
#
# Why: this account allows iam:CreateRole and iam:AttachRolePolicy, but blocks
# iam:ListRolePolicies and iam:ListAttachedRolePolicies. The AWS provider calls
# both of those every time it reads an aws_iam_role / aws_iam_role_policy_attachment
# (to detect drift in inline and managed policies), so those resources fail on
# create here — verified against provider v5 and v6 alike, and there is no flag
# to turn that read off.
#
# Terraform's read of a CloudFormation stack is DescribeStacks, which touches no
# IAM list APIs, so the stack reads cleanly. CloudFormation creates the roles
# using our own (permitted) CreateRole/AttachRolePolicy calls. Everything stays
# declared in Terraform, in one state file, applied and destroyed as one unit.
#
# Role names are left to CloudFormation to generate: fixed names can't be reused
# after a failed run, because deleting a role is also blocked in this account.
# No tags are set on the stack either — CloudFormation would propagate them to
# the roles, which needs the equally-blocked iam:TagRole.
# ---------------------------------------------------------------------------
resource "aws_cloudformation_stack" "eks_iam" {
  name         = "${var.name_prefix}-eks-iam"
  capabilities = ["CAPABILITY_IAM"]

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "IAM roles for the ${local.cluster_name} EKS cluster and its managed node group"

    Resources = {
      ClusterRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { Service = "eks.amazonaws.com" }
              Action    = "sts:AssumeRole"
            }]
          }
          ManagedPolicyArns = [
            "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
          ]
        }
      }

      NodeRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { Service = "ec2.amazonaws.com" }
              Action    = "sts:AssumeRole"
            }]
          }
          # The three policies every EKS worker node needs: join the cluster,
          # run the VPC CNI, and pull images from ECR. infra/iam will add the
          # controller policies (LB Controller, ESO, ExternalDNS, EBS CSI) here.
          ManagedPolicyArns = [
            "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
            "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
            "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
          ]
        }
      }
    }

    Outputs = {
      ClusterRoleArn = { Value = { "Fn::GetAtt" = ["ClusterRole", "Arn"] } }
      NodeRoleArn    = { Value = { "Fn::GetAtt" = ["NodeRole", "Arn"] } }
    }
  })
}

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

  # This account blocks iam:CreateOpenIDConnectProvider, so IRSA is not usable —
  # controllers (LB Controller, ESO, ExternalDNS, EBS CSI) get AWS permissions
  # via the shared node role instead (wired up in infra/iam).
  enable_irsa = false

  # Use the CloudFormation-created roles above instead of letting the module
  # create aws_iam_role resources (see the comment on that stack for why).
  create_iam_role = false
  iam_role_arn    = aws_cloudformation_stack.eks_iam.outputs["ClusterRoleArn"]

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

      # Same story as the cluster role — reuse the CloudFormation-created one.
      create_iam_role = false
      iam_role_arn    = aws_cloudformation_stack.eks_iam.outputs["NodeRoleArn"]
    }
  }
}
