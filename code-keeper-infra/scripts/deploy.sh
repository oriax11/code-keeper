#!/usr/bin/env bash
#
# deploy.sh — initialise, validate and plan the Terraform infrastructure.
#
# Usage: ./scripts/deploy.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/terraform"
[ -d "$TF_DIR" ] || TF_DIR="$ROOT"

cd "$TF_DIR"

echo "== terraform init =="
terraform init -input=false

echo "== terraform fmt =="
terraform fmt

echo "== terraform validate =="
terraform validate

echo "== terraform plan =="
terraform plan -input=false -out=tfplan

echo
echo "Plan saved to $TF_DIR/tfplan."
echo "Apply with:  (cd \"$TF_DIR\" && terraform apply tfplan)"
