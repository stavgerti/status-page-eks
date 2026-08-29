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

variable "domain_name" {
  description = "Subdomain delegated to us by the mentor. We own this zone; the parent zone (lvtvv.com) stays his."
  type        = string
  default     = "devops.lvtvv.com"
}
