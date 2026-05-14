#!/usr/bin/env bash
set -Eeuo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dev}"
REGISTRY_NAME="${REGISTRY_NAME:-dev-registry}"
REGISTRY_PORT="${REGISTRY_PORT:-5111}"

command -v docker >/dev/null || { echo "docker is required"; exit 1; }
command -v k3d >/dev/null || { echo "k3d is required"; exit 1; }
command -v kubectl >/dev/null || { echo "kubectl is required"; exit 1; }

if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
  echo "k3d cluster '$CLUSTER_NAME' already exists."
else
  k3d cluster create "$CLUSTER_NAME" \
    --agents 1 \
    --api-port "6550" \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer" \
    --registry-create "${REGISTRY_NAME}:0.0.0.0:${REGISTRY_PORT}" \
    --wait
fi

kubectl cluster-info

echo
echo "Cluster:  $CLUSTER_NAME"
echo "Registry: localhost:${REGISTRY_PORT}"
echo
echo "Example image workflow:"
echo "  docker build -t localhost:${REGISTRY_PORT}/my-app:dev ."
echo "  docker push localhost:${REGISTRY_PORT}/my-app:dev"
echo
echo "In Kubernetes manifests, use:"
echo "  image: ${REGISTRY_NAME}:5000/my-app:dev"