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

variable "node_ami_type" {
  description = "AMI family for the node group. Stated explicitly rather than left to a default — see the comment in main.tf."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_group_size" {
  description = "Desired/min/max size of the EKS managed node group"
  type = object({
    desired = number
    min     = number
    max     = number
  })
  # Three, not two. Not for CPU or memory — for pod slots. The AWS VPC CNI
  # gives every pod a real VPC IP, and how many a node can hold is fixed by the
  # instance type: a t3.medium supports 3 ENIs x 6 IPs, minus one for the node
  # itself, so 17 pods. Two nodes ran out at 34 once the platform controllers
  # (LB controller, NGINX, cert-manager, ESO, ExternalDNS, ArgoCD, EBS CSI) and
  # the application were running, and kube-prometheus-stack could not schedule:
  #
  #   0/2 nodes are available: 2 Too many pods
  #
  # The third node was always the plan; it was dropped when the self-hosted CI
  # runners left the design. The alternative is VPC CNI prefix delegation,
  # which raises the per-node ceiling to ~110 at no cost, and is the better
  # answer for a long-lived cluster.
  # min stays below desired deliberately. EKS validates a node group update
  # against its *current* state, so raising min and desired together fails with
  # "Minimum capacity 3 can't be greater than desired size 2". There's also no
  # reason for them to match: with no autoscaler running, desired is what sets
  # the node count, and min is only a floor.
  # min is what actually pins the node count here, not desired. The EKS module
  # sets ignore_changes on desired_size — sensible when an autoscaler owns that
  # field, but we have none, so changing `desired` in Terraform is silently
  # discarded. EKS raises the group to satisfy min, so min is the durable knob.
  #
  # Raising min also has to be done from a state where desired already meets it,
  # or EKS rejects the update: "Minimum capacity 3 can't be greater than desired
  # size 2". desired was bumped to 3 out of band once, and min then codifies it.
  default = {
    desired = 3
    min     = 3
    max     = 4
  }
}
