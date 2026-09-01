#!/usr/bin/env bash
#
# Applies the IAM resources in this directory. Idempotent — safe to re-run.
#
# Why this isn't Terraform: see README.md. Short version — the course admin
# asked that IAM stay out of automation in this shared account, and this
# account also blocks the IAM read actions the AWS provider needs in order to
# manage aws_iam_role / aws_iam_role_policy_attachment at all.
#
set -euo pipefail

cd "$(dirname "$0")"

ACCOUNT_ID="992382545251"
CI_ROLE_NAME="stav-status-page-ci"
NODE_ROLE_NAME="stav-status-page-eks-node-role"

# An inline role policy is capped at 10,240 characters. The Load Balancer
# Controller document is the only one anywhere near that, and it currently fits
# with room to spare - but it's maintained upstream by AWS and could grow, so
# fail loudly here rather than getting a confusing LimitExceeded from the API.
check_size() {
  local file="$1" size
  size=$(wc -c < "${file}")
  if [ "${size}" -ge 10240 ]; then
    echo "ERROR: ${file} is ${size} bytes, over the 10240 inline-policy limit." >&2
    echo "       Strip the whitespace, or split it across two inline policies." >&2
    exit 1
  fi
}

echo "==> CI role: ${CI_ROLE_NAME}"

# create-role fails if the role exists; that's the normal case on re-runs, so
# fall back to updating the trust policy in place.
if aws iam get-role --role-name "${CI_ROLE_NAME}" >/dev/null 2>&1; then
  # Deliberately not re-applying the trust policy on an existing role:
  # iam:UpdateAssumeRolePolicy is denied in this account, so the call can only
  # fail. policies/ci-trust-policy.json documents what was set at creation and
  # is the file to use if the role ever has to be recreated.
  echo "    exists — trust policy left as-is (UpdateAssumeRolePolicy is denied here)"
else
  echo "    creating"
  # No --tags: iam:TagRole is denied in this account and passing tags fails
  # the whole call.
  aws iam create-role \
    --role-name "${CI_ROLE_NAME}" \
    --description "GitHub Actions assumes this to push images to ECR" \
    --max-session-duration 3600 \
    --assume-role-policy-document file://policies/ci-trust-policy.json \
    --query 'Role.Arn' --output text
fi

# put-role-policy is an upsert, so this needs no exists-check.
echo "    attaching inline policy: ecr-push"
aws iam put-role-policy \
  --role-name "${CI_ROLE_NAME}" \
  --policy-name ecr-push \
  --policy-document file://policies/ci-ecr-push.json

echo
echo "==> Node role: ${NODE_ROLE_NAME}"

# The cluster controllers get their AWS permissions here rather than through
# per-pod IRSA roles, because iam:CreateOpenIDConnectProvider is denied in this
# account. That's the pre-2019 EKS pattern: legitimate, and the trade-off is
# that every pod on a node shares these permissions.
#
# Inline policies rather than managed ones: iam:CreatePolicy needs iam:TagPolicy
# to succeed the way the CLI sends it, and tagging is denied here. put-role-policy
# is an upsert, so re-running is safe.
put_inline() {
  local policy_name="$1" file="$2"
  check_size "${file}"
  echo "    inline policy: ${policy_name}"
  aws iam put-role-policy \
    --role-name "${NODE_ROLE_NAME}" \
    --policy-name "${policy_name}" \
    --policy-document "file://$(pwd -W 2>/dev/null || pwd)/${file}"
}

put_inline lb-controller   policies/lb-controller.json
put_inline external-secrets policies/external-secrets.json
put_inline externaldns      policies/externaldns.json

# The EBS CSI driver has an AWS-managed policy, so there's nothing to author or
# keep in sync — just attach it. attach-role-policy is idempotent.
echo "    managed policy: AmazonEBSCSIDriverPolicy"
aws iam attach-role-policy \
  --role-name "${NODE_ROLE_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

echo
echo "==> Result"
echo "CI role ARN:"
aws iam get-role --role-name "${CI_ROLE_NAME}" --query 'Role.Arn' --output text
echo "Node role inline policies:"
aws iam list-role-policies --role-name "${NODE_ROLE_NAME}" --query 'PolicyNames' --output text
echo "Node role attached policies:"
aws iam list-attached-role-policies --role-name "${NODE_ROLE_NAME}" --query 'AttachedPolicies[].PolicyName' --output text
