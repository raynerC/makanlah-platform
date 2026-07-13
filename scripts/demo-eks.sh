#!/bin/bash
# Spin up the ephemeral EKS demo: cluster + controllers + the makanlah chart.
# Everything here is destroyed the same session: scripts/nuke-eks.sh
set -euo pipefail

cd "$(dirname "$0")/.."
REGION=us-east-1

echo "=== 1/6 terraform apply (~15 min: control plane is the slow part)"
terraform -chdir=infra/envs/eks-demo init -input=false >/dev/null
terraform -chdir=infra/envs/eks-demo apply -input=false -auto-approve

cluster=$(terraform -chdir=infra/envs/eks-demo output -raw cluster_name)
app_role=$(terraform -chdir=infra/envs/eks-demo output -raw app_role_arn)
alb_role=$(terraform -chdir=infra/envs/eks-demo output -raw alb_controller_role_arn)
vpc=$(terraform -chdir=infra/envs/eks-demo output -raw vpc_id)
menus=$(terraform -chdir=infra/envs/eks-demo output -raw menus_table)
orders=$(terraform -chdir=infra/envs/eks-demo output -raw orders_table)
queue=$(terraform -chdir=infra/envs/eks-demo output -raw order_events_queue_url)

echo "=== 2/6 kubeconfig"
aws eks update-kubeconfig --name "$cluster" --region $REGION

echo "=== 3/6 AWS Load Balancer Controller (IRSA)"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$cluster" \
  --set region=$REGION \
  --set vpcId="$vpc" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$alb_role" \
  --wait --timeout 300s

echo "=== 4/6 metrics-server (HPA needs it)"
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system \
  --set "args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}" \
  --wait --timeout 300s

echo "=== 5/6 kube-prometheus-stack (trimmed for t3.small nodes)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set alertmanager.enabled=false \
  --set prometheus.prometheusSpec.retention=6h \
  --set prometheus.prometheusSpec.resources.requests.cpu=100m \
  --set prometheus.prometheusSpec.resources.requests.memory=350Mi \
  --wait --timeout 600s

echo "=== 6/6 makanlah chart (ECR images, IRSA, ALB ingress)"
tag=$(aws ecr describe-images --repository-name makanlah/menu-service \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' --output text)
echo "deploying image tag: $tag"
kubectl create namespace makanlah --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install makanlah deploy/helm/makanlah -n makanlah \
  --set image.tag="$tag" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$app_role" \
  --set ingress.enabled=true \
  --set services.menu-service.env.MENUS_TABLE="$menus" \
  --set services.order-service.env.ORDERS_TABLE="$orders" \
  --set services.order-service.env.ORDER_EVENTS_QUEUE_URL="$queue" \
  --set services.notify-worker.env.ORDER_EVENTS_QUEUE_URL="$queue" \
  --wait --timeout 300s

echo "waiting for the ALB to provision..."
for i in $(seq 1 40); do
  host=$(kubectl -n makanlah get ingress makanlah -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$host" ] && break
  sleep 10
done
echo ""
echo "platform on EKS: http://$host"
echo "  smoke:   curl http://$host/stalls"
echo "  load:    make demo-eks-load"
echo "  grafana: kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
echo "  NUKE:    bash scripts/nuke-eks.sh   <- do not skip"
