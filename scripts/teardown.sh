#!/usr/bin/env bash
# teardown.sh -- nuke the billable infrastructure between work sessions.
#
# Strategy: Terraform owns almost everything, so `terraform destroy` does the
# heavy lifting. We only manually clear ECR images first, because a repo with
# images in it can block destroy unless force_delete is set.
#
# Usage: ./scripts/teardown.sh [region]
set -euo pipefail

REGION="${1:-us-east-1}"
TF_DIR="terraform/environments/dev"
ECR_REPO="finbank-digital"   # keep in sync with your ECR module

echo "== Teardown in ${REGION} =="

echo -e "\n-- Emptying ECR repo '${ECR_REPO}' (ignore errors if it doesn't exist yet) --"
IMAGE_IDS=$(aws ecr list-images --repository-name "$ECR_REPO" --region "$REGION" \
  --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
if [ "$IMAGE_IDS" != "[]" ] && [ -n "$IMAGE_IDS" ]; then
  aws ecr batch-delete-image --repository-name "$ECR_REPO" --region "$REGION" \
    --image-ids "$IMAGE_IDS" >/dev/null 2>&1 || true
  echo "cleared images"
else
  echo "no images / repo not present"
fi

echo -e "\n-- terraform destroy --"
if [ -d "$TF_DIR" ]; then
  ( cd "$TF_DIR" && terraform destroy -auto-approve )
else
  echo "No terraform dir at $TF_DIR yet -- skipping (nothing provisioned)."
fi

echo -e "\n== Teardown complete. Run ./scripts/cost-check.sh to confirm nothing is left running. =="
