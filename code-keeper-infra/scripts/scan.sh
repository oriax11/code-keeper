#!/usr/bin/env bash
#
# scan.sh — scan container images for HIGH/CRITICAL vulnerabilities with Trivy.
#
# Usage:
#   DOCKERHUB_USER=<user> ./scan.sh [tag]
#   ./scan.sh image1 [image2 ...]
#
set -euo pipefail

REGISTRY="${DOCKERHUB_USER:-}"
TAG="${1:-latest}"

if ! command -v trivy >/dev/null 2>&1; then
  echo "Trivy is not installed. See https://trivy.dev/latest/docs/getting-started/installation/" >&2
  exit 1
fi

if [ "$#" -gt 1 ]; then
  IMAGES=("${@:2}")
elif [ -n "$REGISTRY" ]; then
  IMAGES=(
    "$REGISTRY/api-gateway-app:$TAG"
    "$REGISTRY/inventory-app:$TAG"
    "$REGISTRY/billing-app:$TAG"
    "$REGISTRY/inventory-db:$TAG"
    "$REGISTRY/billing-db:$TAG"
  )
else
  echo "Provide image names or set DOCKERHUB_USER." >&2
  exit 1
fi

status=0
for img in "${IMAGES[@]}"; do
  echo "=== scanning $img ==="
  trivy image --severity HIGH,CRITICAL --exit-code 0 --no-progress "$img" || status=1
done

exit "$status"
