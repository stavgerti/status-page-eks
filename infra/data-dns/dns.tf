# ---------------------------------------------------------------------------
# Public hosted zone for the subdomain the mentor delegated to us.
#
# How the delegation works: he owns lvtvv.com. We create this zone for
# devops.lvtvv.com and hand him its four NS records; he adds them to his zone
# once. From then on AWS answers for everything under devops.lvtvv.com, which
# means:
#   - ExternalDNS can create/update records here on its own
#   - cert-manager can satisfy Let's Encrypt's ownership challenge
# ...without him being in the loop for any future change.
#
# Deliberately NOT creating any records here. The app's record points at a
# load balancer that doesn't exist yet and whose DNS name isn't knowable at
# plan time — ExternalDNS writes it from inside the cluster once the Ingress
# is up. That's exactly the gap ExternalDNS exists to close.
# ---------------------------------------------------------------------------
resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "Delegated subdomain for the Status-Page project"

  tags = {
    Owner   = "stav"
    Project = "status-page-eks"
  }
}

# ---------------------------------------------------------------------------
# Override the zone's SOA to shorten negative caching.
#
# Route 53 creates every zone with a SOA whose final field — the minimum, which
# is what resolvers use as the TTL for NXDOMAIN answers — is 86400. A name that
# doesn't resolve once is therefore remembered as not existing for a full day.
#
# That is a real problem for this stack, not a theoretical one. Records here are
# created at runtime by ExternalDNS once an Ingress appears, while cert-manager
# starts resolving the same name immediately to run its ACME self-check. The
# self-check loses that race by a minute or so, the VPC resolver caches the
# NXDOMAIN, and the certificate then can't be issued for 24 hours even though
# the record exists. Hit exactly this on a smoke test before the app depended
# on it.
#
# 300 seconds instead: still a real cache, but a mistake costs five minutes.
# Every other field is Route 53's default, kept as-is.
# ---------------------------------------------------------------------------
resource "aws_route53_record" "soa" {
  zone_id = aws_route53_zone.main.zone_id
  name    = aws_route53_zone.main.name
  type    = "SOA"
  ttl     = 900

  # The SOA record already exists (Route 53 creates it with the zone), so
  # Terraform has to be told it may take ownership of it.
  allow_overwrite = true

  records = [
    "${aws_route53_zone.main.name_servers[0]}. awsdns-hostmaster.amazon.com. 1 7200 900 1209600 300"
  ]
}
