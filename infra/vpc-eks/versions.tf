terraform {
  required_version = ">= 1.10.0" # 1.10 is where S3-native state locking landed

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # State lives in the S3 bucket created by infra/bootstrap.
  # use_lockfile is S3-native locking (Terraform >= 1.10) — this account has
  # no DynamoDB access, and with S3 locking a lock table isn't needed anyway.
  backend "s3" {
    bucket       = "stav-status-page-eks-tfstate"
    key          = "vpc-eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # No provider-level default_tags: it force-injects tags onto every
  # resource including IAM roles/policies, which need iam:TagRole /
  # iam:TagPolicy (blocked in this account) if they're created with any
  # tags at all. Tagging is applied per-module instead (see main.tf),
  # explicitly skipping IAM sub-resources.
}
