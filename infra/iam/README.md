# infra/iam

IAM for the Status-Page project. **Not Terraform** — plain policy documents plus
an idempotent script.

## Why this isn't Terraform

Two independent reasons, either of which would be enough:

1. **The course admin asked for it.** IAM stays out of automation in this shared
   account.
2. **Terraform physically can't manage IAM here.** The AWS provider reads a role
   back after every create (`iam:ListRolePolicies`, `iam:ListAttachedRolePolicies`)
   to detect policy drift. Both are denied for our user, so `aws_iam_role` and
   `aws_iam_role_policy_attachment` fail on create — verified against provider
   v5 and v6, with no flag to disable that read.

Keeping the policies as reviewable JSON in git gets most of what Terraform would
have given us — diffs, history, code review — without the part that doesn't work.

## Applying

```bash
bash apply.sh
```

Idempotent: creates the role if missing, updates it if present, and upserts the
inline policy either way.

## What's here

### CI role — `stav-status-page-ci`

How GitHub Actions pushes images without holding a long-lived key with broad
access:

1. The workflow authenticates with Stav's personal access key (in GitHub Secrets)
   and calls `sts:AssumeRole`.
2. That returns temporary credentials, valid one hour, carrying only ECR push
   rights to the `status-page` repository.
3. `docker push` runs with those.

The point isn't to defend against the personal key itself leaking out of GitHub's
secret storage — anyone holding that key could bypass the role entirely. It's the
much more common failure: a compromised or malicious Action exfiltrating
environment variables *during a run*. In that case what leaks is a one-hour token
that can only push to one ECR repository.

- `policies/ci-trust-policy.json` — who may assume the role
- `policies/ci-ecr-push.json` — what it may do once assumed

`ecr:GetAuthorizationToken` has to be `Resource: "*"`; it's an account-level call
that takes no resource. Everything else is scoped to the one repository ARN.

**Verified after applying** — assumed the role and confirmed it can fetch an ECR
auth token and read the `status-page` repo, *and* that it's denied reading the
database secret, listing EKS clusters, and touching another student's ECR repo.

#### The workflow must set `role-skip-session-tagging: true`

`aws-actions/configure-aws-credentials` doesn't just call `sts:AssumeRole` — by
default it also attaches session tags recording the repository, workflow and
actor. That needs `sts:TagSession` in the trust policy, and this trust policy
only grants `sts:AssumeRole`, so the action fails with:

```
Could not assume role with user credentials: User: .../stav is not authorized
to perform: sts:TagSession on resource: .../stav-status-page-ci
```

It isn't fixable from this side: `iam:UpdateAssumeRolePolicy` is denied in this
account, so the trust policy on the existing role can't be amended, and creating
a replacement role would strand the current one (deletion is denied too). The
workflow skipping session tagging costs only the CloudTrail metadata about which
run assumed the role — worth having, not worth an extra permission request and
an orphaned role.

Worth noting how this got missed: the role was verified with `aws sts
assume-role` from the CLI, which sends no session tags, so it passed while the
path that actually matters failed. Verify the real caller, not an approximation
of it.

### Node role — `stav-status-page-eks-node-role`

There is no IRSA in this account (`iam:CreateOpenIDConnectProvider` is denied),
so the cluster's controllers take their AWS permissions from the node role
instead of per-pod roles. That's the pre-2019 EKS pattern — legitimate and
explainable, but worth being explicit that the trade-off is real: every pod
scheduled on a node can reach these permissions, not just the controller they
were granted for.

| Policy | Type | For |
|---|---|---|
| `lb-controller` | inline | AWS Load Balancer Controller — provisions the NLB from ingress-nginx's Service |
| `external-secrets` | inline | External Secrets Operator — reads `stav-status-page/*` from Secrets Manager |
| `externaldns` | inline | ExternalDNS — writes records in the `devops.lvtvv.com` zone. cert-manager rides on this one too, see below |
| `AmazonEBSCSIDriverPolicy` | AWS managed | EBS CSI driver — volumes for the Prometheus PVC |

`lb-controller.json` is fetched verbatim from
[the upstream repo](https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json)
rather than hand-written — it's 16 statements of fine-grained EC2 and ELB
permissions, and getting one wrong surfaces as a controller failure much later.
Re-fetch it when upgrading the controller.

Scoping: ExternalDNS can only write to our zone (`Z01048142P6LD2YAPVXYD`); the
Route 53 *list* calls have to be `Resource: "*"` because those APIs take no
resource. ESO is scoped to the `stav-status-page/` secret prefix by wildcard, so
it survives a secret being recreated with a different random ARN suffix.

**Verified after applying:** all four are attached, the ESO resource matches the
secret prefix, and the zone ID in the ExternalDNS policy matches the zone that
actually exists in Route 53.

cert-manager has no policy of its own, but it does call AWS. The original design
used the HTTP-01 challenge, which needs no credentials at all; F5's ingress
controller rejects that solver's temporary Ingress, so the issuers use DNS-01
instead and cert-manager writes a TXT record to prove ownership. It needs
exactly `route53:ChangeResourceRecordSets` on our zone plus the list/GetChange
calls — which is what the `externaldns` policy above already grants, and with no
IRSA here both controllers authenticate as the same node role. So nothing was
added; it is worth knowing the dependency exists. Narrowing the ExternalDNS
policy would silently break certificate renewal.

See `platform/bootstrap/manifests/cluster-issuers.yaml` for the full reasoning.

## Account constraints worth knowing before editing

- ✅ Allowed: `CreateRole`, `AttachRolePolicy`, `PutRolePolicy`, `PassRole`,
  `GetRole`, `CreateInstanceProfile`
- ❌ Denied: all IAM *read* actions on policies (`ListRolePolicies`,
  `ListAttachedRolePolicies`, `GetRolePolicy`, `ListRoleTags`), all tagging
  (`TagRole`, `TagPolicy`), all delete/detach, `CreateOpenIDConnectProvider`

Consequences: never pass `--tags` to `create-role`; prefer inline policies over
managed ones (fewer objects left behind, since deletion is denied); and expect
`terraform destroy` to leave IAM roles orphaned for the admin to clean up.
