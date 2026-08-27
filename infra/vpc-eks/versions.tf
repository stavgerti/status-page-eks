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

  default_tags {
    tags = {
      Owner   = "stav"
      Project = "status-page-eks"
    }
  }
}
