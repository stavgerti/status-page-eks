# ---------------------------------------------------------------------------
# PostgreSQL — the app's system of record.
#
# Run as RDS rather than a Postgres pod in the cluster because losing the
# database is the one failure this project can't shrug off: RDS brings
# automated backups, point-in-time recovery, and (with Multi-AZ) automatic
# failover to a standby in another availability zone.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db"
  subnet_ids = local.private_subnet_ids

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-db" })
}

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "Postgres access for the EKS worker nodes only"
  vpc_id      = local.vpc_id

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-rds" })
}

# Referencing the node security group as the source (rather than a CIDR) means
# the rule stays correct no matter which subnet or IP a pod lands on, and
# nothing outside the cluster can reach the database.
resource "aws_vpc_security_group_ingress_rule" "rds_from_nodes" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from EKS nodes"
  referenced_security_group_id = local.node_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Generated here rather than typed by a human, so the real password never
# exists in a tfvars file, a commit, or a chat message. Excludes the four
# characters RDS rejects in a master password: / @ " and space.
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_instance" "main" {
  identifier = "${var.name_prefix}-db"

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true # uses the default aws/rds key — no KMS permissions needed

  multi_az               = var.db_multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  backup_retention_period = var.db_backup_retention_days
  # Both windows sit in the early hours UTC, and the backup window must not
  # overlap the maintenance window.
  backup_window      = "03:00-04:00"
  maintenance_window = "Mon:04:30-Mon:05:30"

  auto_minor_version_upgrade = true

  # Course project: we want `terraform destroy` to actually complete at the
  # end rather than stopping to ask about a final snapshot.
  skip_final_snapshot = true
  deletion_protection = false

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-db" })
}

# ---------------------------------------------------------------------------
# Credentials in Secrets Manager.
#
# This is what makes External Secrets Operator meaningful in the cluster: ESO
# reads this secret and materialises it as a Kubernetes Secret, so the password
# never passes through git, Helm values, or GitHub Secrets. Stored as JSON with
# the connection details alongside the password, so the app gets everything it
# needs from one place.
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  name        = "${var.name_prefix}/db"
  description = "Postgres credentials and connection details for Status-Page"

  # Without this, a deleted secret sits in a 7-30 day recovery window and the
  # name can't be reused — which would block re-running this stack.
  recovery_window_in_days = 0

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-db" })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = aws_db_instance.main.username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
  })
}
