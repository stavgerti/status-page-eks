# Secrets policy

## Where secrets actually live

- **AWS Secrets Manager** — SECRET_KEY, DB credentials. Injected into pods at
  runtime by External Secrets Operator (`app/helm-chart/templates/externalsecret.yaml`),
  never written into the Helm chart itself.
- **GitHub Actions Secrets** (repo Settings → Secrets and variables → Actions) —
  the personal AWS key used to assume the CI role
  (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`). Referenced in workflows as
  `${{ secrets.* }}`, never inlined.
- **Local `.env` files** — gitignored (`.gitignore` excludes `*.env`, `.env.*`,
  `secrets.yaml`, `*.pem`, `*.key`).

Nothing above should ever appear as a literal value in a commit, a values.yaml
default, a Dockerfile ARG, a workflow file, or a chat/PR/issue comment.

## If a secret leaks anyway

Rotation, not deletion, is what fixes it — a secret pasted anywhere (chat,
commit, PR comment) is compromised the moment it's typed, even if later
removed. `git revert` / force-push does not undo the exposure.

1. **Revoke/rotate it immediately** at the source (GitHub PAT settings, AWS
   IAM console, etc.) before doing anything else.
2. Only then clean up the location it leaked into, if relevant (git history
   rewrite is a separate, optional step — rotation is the part that actually
   closes the hole).

## Enforcement

- **CI**: `.github/workflows/secret-scan.yaml` runs gitleaks against the full
  history of every push and PR — catches a secret even if a later commit
  removed it.
- **Local pre-commit hook** (optional but recommended):
  ```
  git config core.hooksPath scripts/hooks
  ```
  Blocks a commit if the staged diff matches a known secret pattern. Uses
  `gitleaks` if installed (`brew install gitleaks` / see gitleaks releases),
  falls back to a smaller built-in pattern set otherwise.
