#!/usr/bin/env bash
# cost-check.sh -- quick scan of the resources most likely to cost you money.
# Run this at the END of every work session. If anything unexpected is running,
# either you forgot to `terraform destroy` or something was created by hand.
#
# Usage: ./scripts/cost-check.sh [region]
set -euo pipefail

REGION="${1:-us-east-1}"
echo "== Cost check in ${REGION} =="

echo -e "\n-- Running ECS services (Fargate = billed per running task) --"
for cluster in $(aws ecs list-clusters --region "$REGION" --query 'clusterArns[]' --output text); do
  echo "cluster: $cluster"
  aws ecs list-services --cluster "$cluster" --region "$REGION" \
    --query 'serviceArns[]' --output text
done

echo -e "\n-- Load balancers (ALB billed per hour even when idle) --"
aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[].[LoadBalancerName,State.Code]' --output table 2>/dev/null || echo "none / not authorized"

echo -e "\n-- NAT gateways (expensive; this project is designed to NOT need one) --"
aws ec2 describe-nat-gateways --region "$REGION" \
  --filter Name=state,Values=available \
  --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || echo "none"

echo -e "\n-- ECR repos (storage cost is small but not zero) --"
aws ecr describe-repositories --region "$REGION" \
  --query 'repositories[].repositoryName' --output text 2>/dev/null || echo "none"

echo -e "\n== Done. If you see running ECS services / ALBs / NAT gateways you didn't expect, tear them down. =="
