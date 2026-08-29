terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Local state for now; migrates to the S3 backend (infra/bootstrap) once
  # that bucket exists, same as infra/vpc-eks.
}

provider "aws" {
  region = var.aws_region

  # No default_tags: it force-tags IAM resources too, and iam:TagRole /
  # iam:TagPolicy are blocked in this account (learned the hard way in
  # infra/vpc-eks). Tags are set per-resource instead.
}
