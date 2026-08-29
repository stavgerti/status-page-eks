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
