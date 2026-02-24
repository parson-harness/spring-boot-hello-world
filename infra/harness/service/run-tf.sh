#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

command -v terraform >/dev/null || { echo "❌ terraform not found"; exit 1; }
[[ -f main.tf && -f variables.tf && -f terraform.tfvars ]] || { echo "❌ Missing Terraform files"; exit 2; }

: "${HARNESS_ACCOUNT_ID:?set HARNESS_ACCOUNT_ID}"
: "${HARNESS_PLATFORM_API_KEY:?set HARNESS_PLATFORM_API_KEY}"
export HARNESS_ORG_ID="${HARNESS_ORG_ID:-}"
export HARNESS_PROJECT_ID="${HARNESS_PROJECT_ID:-}"

# Build the final args array (never empty)
apply_args=(-auto-approve -input=false)
[[ -n "${IMAGE_TAG:-}"  ]] && apply_args+=(-var "image_tag=${IMAGE_TAG}")
[[ -n "${IMAGE_REPO:-}" ]] && apply_args+=(-var "image_repo=${IMAGE_REPO}")

terraform init -input=false
terraform apply "${apply_args[@]}"

echo "✅ Harness Service registered/updated."
