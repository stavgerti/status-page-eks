# ---------------------------------------------------------------------------
# Django's SECRET_KEY.
#
# Django refuses to start without it, and it signs sessions, password-reset
# tokens and CSRF tokens — so it belongs in Secrets Manager alongside the
# database credentials, not in a ConfigMap or Helm values.
#
# Kept as its own secret rather than folded into stav-status-page/db: it has
# nothing to do with the database, so a future database credential rotation
# shouldn't touch the key that invalidates every user session.
# ---------------------------------------------------------------------------

# Django's own `get_random_secret_key()` draws from a 50-character alphabet at
# length 50. Matching that here, and avoiding quotes/backslashes that tend to
# get mangled passing through YAML and shell layers on the way to the pod.
resource "random_password" "django_secret_key" {
  length           = 50
  special          = true
  override_special = "!@#%^&*(-_=+)"
}

resource "aws_secretsmanager_secret" "django" {
  name        = "${var.name_prefix}/django"
  description = "Django SECRET_KEY for Status-Page"

  # Same reasoning as the DB secret: without this, a deleted secret sits in a
  # recovery window and its name can't be reused, which would block re-running
  # this stack.
  recovery_window_in_days = 0

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-django" })
}

resource "aws_secretsmanager_secret_version" "django" {
  secret_id = aws_secretsmanager_secret.django.id

  # JSON with a single property, to match the shape of the DB secret so the
  # Helm chart's ExternalSecret entries all look the same (remoteKey + property).
  secret_string = jsonencode({
    secret_key = random_password.django_secret_key.result
  })
}
