terraform {
  required_version = ">= 1.10.0" # 1.10 is where S3-native state locking landed

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Deliberately NO backend block: this is the config that *creates* the
  # backend bucket, so it can't store its own state there. It keeps local
  # state, and it's the only directory in the repo that does.
  #
  # That's the standard bootstrap chicken-and-egg tradeoff. It's low risk
  # here because this config owns exactly one long-lived resource (the
  # bucket) and almost never changes after the first apply.
}

provider "aws" {
  region = var.aws_region
}
