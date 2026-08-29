terraform {
  required_version = ">= 1.10.0"

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
    key          = "data-dns/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  # No default_tags: it force-tags IAM resources too, and iam:TagRole /
  # iam:TagPolicy are blocked in this account (learned the hard way in
  # infra/vpc-eks). Tags are set per-resource instead.
}
