# platform/bootstrap

The cluster-level controllers, installed with Helm. Values files and manifests
live here so every choice is reviewable; `install.sh` applies them and is safe
to re-run.

```bash
bash install.sh
```

**Why Helm and not ArgoCD:** ArgoCD is installed by this script, and having it
manage its own installation is a bootstrap problem with no clean answer. The
split is Helm owns the platform, ArgoCD owns the application.

## What gets installed

| Component | Chart | Purpose |
|---|---|---|
| AWS Load Balancer Controller | `eks/aws-load-balancer-controller` | Turns the ingress controller's Service into an NLB |
| NGINX Ingress Controller | `nginx-stable/nginx-ingress` | Routes HTTP, terminates TLS in-cluster |
| cert-manager | `jetstack/cert-manager` | Issues and renews the Let's Encrypt certificate |
| External Secrets Operator | `external-secrets/external-secrets` | Pulls secrets from AWS Secrets Manager |
| ExternalDNS | `external-dns/external-dns` | Writes Route 53 records from Ingress objects |

Order matters: the load balancer controller has to exist before anything asks
for a `Service` of type `LoadBalancer`.

## Two things worth knowing before changing anything here

### This is NOT `kubernetes/ingress-nginx`

There are two ingress controllers wrapping the same NGINX proxy, with nearly
identical names:

- `kubernetes/ingress-nginx` — the Kubernetes community one, by far the more
  widely deployed. **Archived 2026-03-24.** No further releases, bug fixes, or
  security patches, and its own README says not to deploy it if you aren't
  already using it.
- `nginx/kubernetes-ingress` — F5/NGINX's own, actively maintained, Apache 2.0.
  **This is what's installed here.**

It registers the same `nginx` ingress class, so the application chart didn't
change. What does differ is annotation syntax: `nginx.org/*` here, not
`nginx.ingress.kubernetes.io/*`. That only matters when tuning things like
timeouts or body size — the cert-manager annotation is unaffected.

Traefik and a Gateway API implementation were both considered. Either would have
meant changing the application chart (a class name, or rewriting Ingress as
HTTPRoute) for no gain over a maintained NGINX.

### No IRSA — everything authenticates through the node role

`iam:CreateOpenIDConnectProvider` is denied in this account, so there is no OIDC
provider and no per-pod AWS identity. The LB Controller, ESO and ExternalDNS all
fall through to instance metadata and pick up the node role, which `infra/iam`
has granted their policies.

State it plainly rather than glossing it: this is the pre-2019 EKS pattern, and
the cost is that any pod on a node can reach those permissions, not just the
controller they were meant for. The policies are scoped as tightly as the APIs
allow (ExternalDNS to our zone only, ESO to the `stav-status-page/` prefix) to
limit what that would expose.

cert-manager needs no AWS permissions at all — the HTTP-01 challenge is served
over HTTP through the ingress controller and never calls AWS.

## Cluster-scoped resources

**`manifests/cluster-issuers.yaml`** — `letsencrypt-staging` and
`letsencrypt-prod`.

Point anything new at **staging first**. Production allows 5 duplicate
certificates per week with no way to lift the limit early, so debugging against
it can lock you out for days. Staging certificates are untrusted by browsers but
effectively unlimited, and they prove the whole chain: DNS resolves, the NLB
routes port 80, the ingress controller serves the challenge, cert-manager writes
the Secret.

**`manifests/cluster-secret-store.yaml`** — `aws-secrets-manager`, the store name
the application chart references. Cluster-scoped so the chart can use it from any
namespace without needing a store of its own.

## Gotcha found the hard way: DNS negative caching

Route 53 creates every zone with a SOA whose minimum is 86400, and that value is
what resolvers use as the TTL for NXDOMAIN.

That collides with how this stack works. ExternalDNS creates a record only after
the Ingress exists, while cert-manager starts resolving the same name
immediately for its ACME self-check. The self-check loses by about a minute, the
VPC resolver caches the NXDOMAIN, and the certificate can't be issued **for 24
hours** even though the record is there.

Fixed in `infra/data-dns` by overriding the SOA minimum to 300. Worth knowing
that Let's Encrypt itself was never blocked — it queries the authoritative
nameservers directly. Only cert-manager's in-cluster preflight was affected.

## Verified at install time

- The NLB was created and is `internet-facing` across both AZs
- ExternalDNS created a record for a test Ingress, and removed it again when the
  Ingress went away (its `sync` policy working, not just `upsert-only`)
- HTTP reached the ingress controller through the NLB
- Both ClusterIssuers registered ACME accounts with Let's Encrypt (`Ready=True`)
- The ClusterSecretStore validated against Secrets Manager, and a test
  ExternalSecret materialised the real database and Django secrets with the
  correct value lengths
