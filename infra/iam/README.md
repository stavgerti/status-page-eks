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

### Node role policies — not here yet

The AWS Load Balancer Controller, EBS CSI Driver, External Secrets Operator and
ExternalDNS all need AWS permissions via the node role, since this account has no
IRSA (`iam:CreateOpenIDConnectProvider` is denied).

Deliberately deferred: there are no nodes yet (the node group is blocked on IAM
read permissions from the admin), so nothing that needs those permissions can
actually run, and `ListAttachedRolePolicies` being denied means we can't even
inspect what's attached. Writing and applying them now would be doing it blind
and unverifiable. cert-manager, for what it's worth, needs no AWS permissions at
all — the HTTP-01 challenge never touches AWS.

## Account constraints worth knowing before editing

- ✅ Allowed: `CreateRole`, `AttachRolePolicy`, `PutRolePolicy`, `PassRole`,
  `GetRole`, `CreateInstanceProfile`
- ❌ Denied: all IAM *read* actions on policies (`ListRolePolicies`,
  `ListAttachedRolePolicies`, `GetRolePolicy`, `ListRoleTags`), all tagging
  (`TagRole`, `TagPolicy`), all delete/detach, `CreateOpenIDConnectProvider`

Consequences: never pass `--tags` to `create-role`; prefer inline policies over
managed ones (fewer objects left behind, since deletion is denied); and expect
`terraform destroy` to leave IAM roles orphaned for the admin to clean up.
