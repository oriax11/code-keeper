#!/usr/bin/env bash
#
# cleanup.sh — destroy the Terraform infrastructure to stop billing.
#
# Usage: ./scripts/cleanup.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="$ROOT/terraform"
[ -d "$TF_DIR" ] || TF_DIR="$ROOT"

cd "$TF_DIR"

echo "== terraform destroy =="
terraform destroy -input=false -auto-approve

echo
echo "Infrastructure destroyed."
echo "Remove the deployer IAM user/key with:"
echo "  $ROOT/scripts/bootstrap-iam.sh --cleanup cloud-design-deployer"
