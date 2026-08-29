variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Must be globally unique across all of AWS."
  type        = string
  default     = "stav-status-page-eks-tfstate"
}
