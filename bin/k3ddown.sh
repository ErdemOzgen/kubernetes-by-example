#!/usr/bin/env bash
set -Eeuo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-dev}"
REGISTRY_NAME="${REGISTRY_NAME:-dev-registry}"

command -v k3d >/dev/null || { echo "k3d is required"; exit 1; }

k3d cluster delete "$CLUSTER_NAME" || true

# Cleanup registry if it remains after cluster deletion.
k3d registry delete "$REGISTRY_NAME" >/dev/null 2>&1 || true
k3d registry delete "k3d-${REGISTRY_NAME}" >/dev/null 2>&1 || true

echo "Deleted k3d cluster '$CLUSTER_NAME' and registry '$REGISTRY_NAME' if present."