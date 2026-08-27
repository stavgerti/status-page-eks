terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # No backend block yet — using local state until infra/data-dns creates
  # the S3 + DynamoDB backend, then this gets migrated with
  # `terraform init -migrate-state`.
}

provider "aws" {
  region = var.aws_region

  # No provider-level default_tags: it force-injects tags onto every
  # resource including IAM roles/policies, which need iam:TagRole /
  # iam:TagPolicy (blocked in this account) if they're created with any
  # tags at all. Tagging is applied per-module instead (see main.tf),
  # explicitly skipping IAM sub-resources.
}
