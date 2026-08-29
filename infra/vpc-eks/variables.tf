variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names, to avoid collisions with other students in the shared course account"
  type        = string
  default     = "stav-status-page"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.36"

  # Check `aws eks describe-cluster-versions` before changing this — a version
  # can still be accepted by the API long after its standard support has ended,
  # at which point EKS bills the control plane at the much higher extended
  # support rate. 1.31 was originally set here and was already nine months past
  # end-of-standard-support.
  validation {
    condition     = contains(["1.34", "1.35", "1.36"], var.cluster_version)
    error_message = "Pick a version still in EKS standard support (as of 2026-08: 1.34, 1.35, 1.36). Re-check with `aws eks describe-cluster-versions`."
  }
}

variable "node_instance_type" {
  description = "EC2 instance type for the EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "cluster_iam_role_arn" {
  description = "ARN of the manually-created EKS cluster IAM role (see main.tf for why this isn't Terraform-managed)"
  type        = string
}

variable "node_iam_role_arn" {
  description = "ARN of the manually-created EKS node group IAM role (see main.tf for why this isn't Terraform-managed)"
  type        = string
}

variable "node_group_size" {
  description = "Desired/min/max size of the EKS managed node group"
  type = object({
    desired = number
    min     = number
    max     = number
  })
  default = {
    desired = 2
    min     = 2
    max     = 2
  }
}
