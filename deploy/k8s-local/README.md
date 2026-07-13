# deploy/k8s-local — the platform on kind (free Kubernetes practice)

Plain manifests, no Helm: the learning artifact. Same topology as production —
DynamoDB Local and ElasticMQ stand in for AWS, an init Job creates the tables.

```sh
kind create cluster --name makanlah
kind load docker-image makanlah/menu-service:latest makanlah/order-service:latest makanlah/notify-worker:latest --name makanlah
kubectl apply -f deploy/k8s-local/
kubectl -n makanlah wait --for=condition=available deployment --all --timeout=180s

# try it
kubectl -n makanlah port-forward svc/menu-service 8081:8000 &
kubectl -n makanlah port-forward svc/order-service 8082:8000 &
bash scripts/demo-order.sh          # same demo as compose — it only needs the two ports

# tear down
kind delete cluster --name makanlah
```

Files `30–32` are the raw-manifest versions of the three app services — kept as the
learning artifact. The canonical flow (`make k8s-local-up`) applies the backing
services from here and installs the apps via the Helm chart
(`deploy/helm/makanlah` with `values-local.yaml`), so the chart is exercised locally
before it ever touches EKS.

Details that carry over to EKS:

- liveness (`/healthz`) vs readiness (`/readyz`) probes on the APIs; the worker's
  liveness is an exec probe on its heartbeat file (no HTTP port)
- resource requests/limits on everything (HPA math needs requests)
- `imagePullPolicy: Never` is kind-only — the Helm chart flips to ECR images
