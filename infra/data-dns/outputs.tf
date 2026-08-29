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
