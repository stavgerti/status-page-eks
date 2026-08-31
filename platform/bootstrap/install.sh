#!/usr/bin/env bash
#
# Installs the cluster-level controllers. Idempotent — `helm upgrade --install`
# and `kubectl apply` can both be re-run safely.
#
# These are deliberately NOT managed by ArgoCD. ArgoCD is one of the things
# installed here, and having it manage its own installation is a bootstrap
# problem nobody needs. The split is: Helm owns the platform, ArgoCD owns the
# application.
#
# Order matters. The load balancer controller has to exist before the ingress
# controller asks for a Service of type LoadBalancer, or the request goes
# unfulfilled.
#
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER_NAME="stav-status-page-eks"
REGION="us-east-1"

echo "==> Helm repositories"
helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo add nginx-stable https://helm.nginx.com/stable >/dev/null
helm repo add jetstack https://charts.jetstack.io >/dev/null
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns >/dev/null
helm repo update >/dev/null

echo "==> AWS Load Balancer Controller"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --values values/aws-load-balancer-controller.yaml \
  --wait --timeout 8m

# nginx/kubernetes-ingress (F5's), NOT kubernetes/ingress-nginx — the community
# one was archived 2026-03-24 and gets no further security fixes. See README.
echo "==> NGINX Ingress Controller"
helm upgrade --install nginx-ingress nginx-stable/nginx-ingress \
  --namespace nginx-ingress --create-namespace \
  --values values/nginx-ingress.yaml \
  --wait --timeout 8m

echo "==> cert-manager"
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --values values/cert-manager.yaml \
  --wait --timeout 8m

echo "==> External Secrets Operator"
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --values values/external-secrets.yaml \
  --wait --timeout 8m

echo "==> ExternalDNS"
helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns --create-namespace \
  --values values/external-dns.yaml \
  --wait --timeout 8m

# Applied after their operators so the CRDs they depend on already exist.
echo "==> Cluster-scoped resources"
kubectl apply -f manifests/cluster-issuers.yaml
kubectl apply -f manifests/cluster-secret-store.yaml

echo
echo "==> Status"
kubectl get clusterissuer
kubectl get clustersecretstore
echo
echo "Ingress load balancer:"
kubectl get svc -n nginx-ingress nginx-ingress-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
