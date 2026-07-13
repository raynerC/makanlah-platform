#!/bin/bash
# Tear down the ephemeral EKS demo. Helm releases with AWS-side resources
# (the ingress ALB) must go first or terraform destroy hits orphaned ENIs.
set -uo pipefail

cd "$(dirname "$0")/.."

echo "=== deleting helm releases (removes the controller-created ALB)"
helm uninstall makanlah -n makanlah --wait --timeout 300s 2>/dev/null
helm uninstall monitoring -n monitoring --wait --timeout 300s 2>/dev/null
helm uninstall aws-load-balancer-controller -n kube-system --wait --timeout 120s 2>/dev/null
sleep 30 # let the controller finish deleting the ALB before it disappears

echo "=== terraform destroy"
terraform -chdir=infra/envs/eks-demo destroy -input=false -auto-approve

echo "=== audit"
bash scripts/aws-audit.sh | tail -3
