# ---------------------------------------------------------------------------
# Redis — the RQ job broker for the rq-worker and rq-scheduler processes.
#
# Deliberately a SINGLE node, unlike the Multi-AZ database. Redis here holds a
# work queue, not the system of record: if it's lost, queued background jobs
# are lost with it but the site itself keeps serving, and the data is
# reconstructible from Postgres. Paying double for a standby doesn't buy much
# against that failure mode — the opposite call from RDS, for a reason worth
# being able to explain.
# ---------------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = local.private_subnet_ids

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-redis" })
}

resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis"
  description = "Redis access for the EKS worker nodes only"
  vpc_id      = local.vpc_id

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-redis" })
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_nodes" {
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis from EKS nodes"
  referenced_security_group_id = local.node_security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# A replication group holding a single node, rather than the older standalone
# aws_elasticache_cluster: it's the resource AWS steers Redis at now, it's the
# only one that supports encryption at rest, and adding a replica later is a
# config change instead of a replacement.
resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "RQ job broker for Status-Page"

  engine         = "redis"
  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type
  port           = 6379

  num_cache_clusters         = 1
  automatic_failover_enabled = false # single node, so there's nothing to fail over to
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # Encrypted at rest — free and invisible to clients. In-transit encryption is
  # deliberately left off: it would require django-rq to be configured for TLS
  # on Ilan's side for no real gain here, since Redis sits in a private subnet
  # reachable only from the cluster's own nodes.
  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

  maintenance_window       = "Mon:05:30-Mon:06:30"
  snapshot_retention_limit = 0 # a job queue isn't worth snapshotting

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-redis" })
}
