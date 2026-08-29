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

# --- RDS -------------------------------------------------------------------

variable "db_engine_version" {
  description = "PostgreSQL major.minor version. Check `aws rds describe-db-engine-versions --engine postgres` before changing."
  type        = string
  default     = "17.9"
}

variable "db_instance_class" {
  description = "RDS instance class. Must be Multi-AZ capable if db_multi_az is true — verify with `aws rds describe-orderable-db-instance-options`."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Name of the database the app connects to"
  type        = string
  default     = "statuspage"
}

variable "db_username" {
  description = "Master username. The password is generated, never set here."
  type        = string
  default     = "statuspage"
}

variable "db_allocated_storage" {
  description = "Storage in GB"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Run a synchronous standby in a second AZ with automatic failover. On by default: reliability was the stated reason for choosing RDS over an in-cluster Postgres."
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  description = "Days of automated backups to keep (also what point-in-time recovery can reach back to)"
  type        = number
  default     = 7
}

# --- ElastiCache -----------------------------------------------------------

variable "redis_engine_version" {
  description = "Redis version. Check `aws elasticache describe-cache-engine-versions --engine redis` before changing."
  type        = string
  default     = "7.1"
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}
