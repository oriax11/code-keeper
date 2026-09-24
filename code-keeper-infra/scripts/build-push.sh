#!/usr/bin/env bash
#
# build-push.sh — build and push the microservice images to Docker Hub.
#
# Expects per-service source/Dockerfiles under docker/<service>/.
# Usage:
#   DOCKERHUB_USER=<user> ./build-push.sh [tag]
#
set -euo pipefail

REGISTRY="${DOCKERHUB_USER:?set DOCKERHUB_USER to your Docker Hub username}"
TAG="${1:-latest}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SERVICES=(api-gateway-app inventory-app billing-app inventory-db billing-db)

for svc in "${SERVICES[@]}"; do
  context="$ROOT/docker/$svc"
  if [ ! -d "$context" ]; then
    echo "skip $svc (no $context)"
    continue
  fi
  echo "== build $REGISTRY/$svc:$TAG =="
  docker build -t "$REGISTRY/$svc:$TAG" "$context"
  echo "== push  $REGISTRY/$svc:$TAG =="
  docker push "$REGISTRY/$svc:$TAG"
done

# rabbit-queue may be an upstream/custom image; build only if a Dockerfile exists.
if [ -d "$ROOT/docker/rabbit-queue" ]; then
  docker build -t "$REGISTRY/rabbit-queue:$TAG" "$ROOT/docker/rabbit-queue"
  docker push "$REGISTRY/rabbit-queue:$TAG"
fi

echo "done."
