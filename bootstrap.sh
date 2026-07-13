#!/usr/bin/env bash

set -Eeuo pipefail


CLUSTER_NAME="squareops"
MANIFEST_DIR="k8s-specifications"
INGRESS_NAMESPACE="ingress-nginx"
INGRESS_MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml"

log() {
  echo
  echo "==> $1"
}

error() {
  echo
  echo "ERROR: $1" >&2
  exit 1
}

log "Checking required tools"

for tool in docker kind kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    error "'$tool' is not installed or not available in PATH."
  fi
done

if ! docker info >/dev/null 2>&1; then
  error "Docker is not running. Start Docker Desktop and try again."
fi

log "Checking kind cluster"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster '$CLUSTER_NAME' already exists. Reusing it."
else
  echo "Creating kind cluster '$CLUSTER_NAME'..."
  kind create cluster --name "$CLUSTER_NAME"
fi

log "Switching kubectl context"

kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null

log "Installing NGINX Ingress Controller"

kubectl apply -f "$INGRESS_MANIFEST_URL"

log "Waiting for NGINX Ingress Controller"

kubectl wait \
  --namespace "$INGRESS_NAMESPACE" \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

log "Deploying voting application"

kubectl apply -f "$MANIFEST_DIR/"

log "Waiting for PostgreSQL StatefulSet"

kubectl rollout status statefulset/db --timeout=180s

log "Waiting for application deployments"

for deployment in redis vote result worker; do
  echo "Waiting for deployment/$deployment..."
  kubectl rollout status "deployment/$deployment" --timeout=180s
done

log "Verifying pods"

kubectl get pods

echo
echo "============================================================"
echo " SquareOps Voting App deployed successfully"
echo "============================================================"
echo
echo "To access both frontends through NGINX Ingress, run:"
echo
echo "  kubectl port-forward --address 0.0.0.0 \\"
echo "    -n ingress-nginx service/ingress-nginx-controller 8090:80"
echo
echo "Then open:"
echo
echo "  Vote:   http://vote.localhost:8090"
echo "  Result: http://result.localhost:8090"
echo
echo "============================================================"
