# Status-Page on Amazon EKS

Production infrastructure for the open-source [Status-Page](https://github.com/Status-Page/Status-Page) app (Django) — a DevOps final project.

## Stack

Terraform · Amazon EKS (managed node group) · ArgoCD (GitOps) · Helm · AWS Load Balancer Controller · ExternalDNS · External Secrets Operator · Actions Runner Controller (self-hosted CI runners) · Prometheus + Grafana · RDS PostgreSQL · ElastiCache Redis · Route 53 + ACM

Architecture diagrams (kept in sync):
- Hebrew: https://claude.ai/code/artifact/9d3d9810-9616-44ed-8519-729db13e1577
- English: https://claude.ai/code/artifact/58032f1c-a272-46a8-9a1b-ffb18c7c5b3f

## Repo layout

```
infra/        Terraform: VPC, EKS, node group, IAM, RDS, ElastiCache, Route 53, ACM
platform/     Helm values / bootstrap manifests for cluster-level controllers
              (ArgoCD, AWS Load Balancer Controller, ExternalDNS, ESO, ARC, kube-prometheus-stack)
app/          Dockerfile, Django production config
helm/         Helm chart for the Status-Page application itself
              (Deployments, Ingress, Service, migration hook, ExternalSecret)
.github/
  workflows/  CI/CD pipeline (build → assume role → push to ECR → bump tag)
```

## Work split

| Owner | Scope | Branch |
|---|---|---|
| Stav | Terraform: VPC, EKS, node group | `infra/vpc-eks` |
| Stav | IAM: node role policies, CI role (`sts:AssumeRole`) | `infra/iam` |
| Stav | RDS, ElastiCache, state backend, Route 53, ACM | `infra/data-dns` |
| Stav | Bootstrap: ArgoCD, LB Controller, ExternalDNS, ESO, ARC, kube-prometheus-stack | `platform/bootstrap` |
| Ilan | Dockerfile, Django production config | `app/container-config` |
| Ilan | Helm chart: Deployments, Ingress, Service, migration hook, probes, ExternalSecret | `app/helm-chart` |
| Ilan | GitHub Actions: build → assume role → push → bump tag | `app/cicd` |

**Dependency:** `app/cicd` needs `infra/iam` (the CI role) and `platform/bootstrap` (the runners) merged first.

## Workflow

Branch → PR → review by the other person → merge. No direct pushes to `main`.
