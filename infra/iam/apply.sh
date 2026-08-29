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

echo "==> CI role: ${CI_ROLE_NAME}"

# create-role fails if the role exists; that's the normal case on re-runs, so
# fall back to updating the trust policy in place.
if aws iam get-role --role-name "${CI_ROLE_NAME}" >/dev/null 2>&1; then
  echo "    exists — updating trust policy"
  aws iam update-assume-role-policy \
    --role-name "${CI_ROLE_NAME}" \
    --policy-document file://policies/ci-trust-policy.json
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
echo "Done. Role ARN:"
aws iam get-role --role-name "${CI_ROLE_NAME}" --query 'Role.Arn' --output text
