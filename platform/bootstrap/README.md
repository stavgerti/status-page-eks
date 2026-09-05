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
| kube-prometheus-stack | `prometheus-community/kube-prometheus-stack` | Prometheus, Grafana, Alertmanager - cluster and pod metrics |

Order matters: the load balancer controller has to exist before anything asks
for a `Service` of type `LoadBalancer`.

## Monitoring

kube-prometheus-stack gives cluster-wide metrics for free: CPU, memory,
network and disk for every pod, including the application's, via node-exporter
and kube-state-metrics. `values/kube-prometheus-stack.yaml` turns off the
control-plane scrape targets (`kubeControllerManager`, `kubeScheduler`,
`kubeEtcd`, `kubeProxy`) since EKS doesn't expose them - they'd sit permanently
red otherwise.

`serviceMonitorSelectorNilUsesHelmValues: false` (and the Pod/Rule
equivalents) means Prometheus picks up any ServiceMonitor in the cluster, not
just ones it created - the application's own ServiceMonitor
(`app/helm-chart`, wiring django-prometheus for request/DB metrics) is
scraped without any change needed here.

Grafana is at **https://grafana.devops.lvtvv.com**, on the mentor's
recommendation. Exposing it needed no new infrastructure at all - the values
file gained an Ingress, and ExternalDNS wrote the A record while cert-manager
issued the certificate. No second load balancer either: the existing ingress
controller routes by hostname.

The Service stays `ClusterIP`; the ingress controller reaches it from inside
the cluster. `port-forward` still works and is the fallback if DNS or the
certificate ever break:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Issued against `letsencrypt-staging` first, per the rule below, and moved to
`letsencrypt-prod` only after staging came back Ready and the host actually
served Grafana's login page.

`grafana.ini` sets `root_url` - without it Grafana builds redirects and asset
links from the request it sees behind the proxy and the login redirect breaks.
Sign-up and anonymous access are both disabled explicitly now that the page is
reachable from the internet.

### Changing the admin password

The password lives in **two places that can disagree**, and that is the whole
difficulty:

- the `kube-prometheus-stack-grafana` Secret, key `admin-password` - what the
  chart sets and what you read it back from
- Grafana's own SQLite database on the PVC - **what login actually checks**

`grafana.adminPassword` in the chart only reaches the database when Grafana
creates the admin user, which happens once, on the first start against an
empty volume. With `persistence` enabled that user already exists, so a
`helm upgrade` updates the Secret and the env var and changes nothing about
what you can log in with. It looks like it worked and it did not.

Read the current one:

```bash
kubectl get secret -n monitoring kube-prometheus-stack-grafana   -o jsonpath='{.data.admin-password}' | base64 -d
```

**Through the UI** (simplest, and what a person should normally do):
Profile → Change password, or `/profile/password` directly. Note that this
writes to the database only - the Secret then holds a stale value, and the
command above will hand you a password that no longer works. Update the Secret
too if you want it to stay the recovery path.

**From the command line**, three steps, none of them optional:

```bash
PW='<the new password>'

# 1. Secret and env var, so a future pod start agrees with the database
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack   --namespace monitoring --values values/kube-prometheus-stack.yaml   --set grafana.adminPassword="$PW"

# 2. The database - the part that actually gates login.
#    --configOverrides is required: without it the CLI writes to its own
#    default data path (/usr/share/grafana/data) instead of the mounted volume,
#    and still prints "Admin password changed successfully".
GPOD=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana   -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n monitoring "$GPOD" -c grafana --   grafana cli --homepath /usr/share/grafana   --configOverrides cfg:default.paths.data=/var/lib/grafana   admin reset-admin-password "$PW"

# 3. Restart. The running process holds the user in memory; without this the
#    database is correct and login still fails.
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
```

Then verify against the endpoint a browser actually uses, and check that a
wrong password is still rejected - otherwise you have only proven the endpoint
answers, not that it authenticates:

```bash
curl -s -o /dev/null -w '%{http_code}
' -X POST   -H 'Content-Type: application/json'   -d "{\"user\":\"admin\",\"password\":\"$PW\"}"   https://grafana.devops.lvtvv.com/login       # expect 200
```

Do not verify with basic auth against `/api/*`: a wrong password and a correct
one both come back 401 there, so the test cannot fail informatively.

Re-running `install.sh` without `GRAFANA_ADMIN_PASSWORD` set writes an empty
value into the Secret. That does not lock you out today, since login reads the
database - but it does destroy the recovery path, and the next pod that starts
against a fresh volume would provision with no password at all. Always pass it,
or recover the current value first and pass that through.

**The trade-off is real and worth stating.** This is now a second admin surface
on the public internet, behind a single static password, alongside ArgoCD. The
honest answer to "would you ship this?" is no - it wants SSO or an OAuth proxy
in front. The password is long and the page is TLS-only, which is the floor,
not the bar.

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

cert-manager is part of this too. HTTP-01 was the original design and needs no
AWS credentials, but F5's controller rejects the solver's temporary Ingress (see
`manifests/cluster-issuers.yaml`), so the issuers use DNS-01 — which writes a TXT
record and therefore does call Route 53. It has no policy of its own: the
`externaldns` inline policy on the node role already allows exactly those calls
on our zone, and without IRSA both controllers arrive as the same node role.
Worth knowing before narrowing that policy: it would break certificate renewal,
not just ExternalDNS.

## Cluster-scoped resources

**`manifests/cluster-issuers.yaml`** — `letsencrypt-staging` and
`letsencrypt-prod`, both solving **DNS-01** against our Route 53 zone. That file
carries the full explanation of why not HTTP-01.

Point anything new at **staging first**. Production allows 5 duplicate
certificates per week with no way to lift the limit early, so debugging against
it can lock you out for days. Staging certificates are untrusted by browsers but
effectively unlimited, and they prove the whole chain: cert-manager can write the
TXT record, Let's Encrypt can resolve it, and the signed certificate lands in the
Secret the Ingress references.

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
