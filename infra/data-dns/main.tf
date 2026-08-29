# Networking for the data layer comes from the infra/vpc-eks stack. Reading it
# through remote state (rather than copying IDs into tfvars or looking them up
# by tag) keeps the dependency explicit: if vpc-eks is rebuilt, the new IDs
# flow through on the next plan.
data "terraform_remote_state" "vpc_eks" {
  backend = "s3"

  config = {
    bucket = "stav-status-page-eks-tfstate"
    key    = "vpc-eks/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  vpc_id             = data.terraform_remote_state.vpc_eks.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc_eks.outputs.private_subnet_ids

  # Pods get VPC IPs from the CNI, so their traffic reaches RDS/Redis with the
  # worker nodes' security group as the source. This is what the data-layer
  # security groups allow inbound from.
  node_security_group_id = data.terraform_remote_state.vpc_eks.outputs.node_security_group_id

  common_tags = {
    Owner   = "stav"
    Project = "status-page-eks"
  }
}
