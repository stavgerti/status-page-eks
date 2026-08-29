output "zone_id" {
  description = "Route 53 hosted zone ID — needed by ExternalDNS and cert-manager"
  value       = aws_route53_zone.main.zone_id
}

output "domain_name" {
  description = "The delegated domain this zone is authoritative for"
  value       = aws_route53_zone.main.name
}

output "name_servers" {
  description = "The four NS records to send the mentor — he adds these to lvtvv.com to complete the delegation"
  value       = aws_route53_zone.main.name_servers
}

# --- Data layer ------------------------------------------------------------

output "db_endpoint" {
  description = "Postgres host:port"
  value       = aws_db_instance.main.endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager secret holding the DB credentials — this is what External Secrets Operator reads, and what infra/iam must grant the node role access to"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  description = "Secrets Manager secret name, for the ExternalSecret manifest in the Helm chart"
  value       = aws_secretsmanager_secret.db.name
}

output "redis_endpoint" {
  description = "Redis host — not a secret, so it can go straight into Helm values rather than through ESO"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.main.port
}
