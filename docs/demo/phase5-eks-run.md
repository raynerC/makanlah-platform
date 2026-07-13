# Phase 5 evidence — the platform on Kubernetes (2026-07-13)

Two halves: free local practice on **kind** (PR #18), then the **ephemeral EKS** run
(PR #19). Same Helm chart both times — `values-local.yaml` for kind, EKS values with
IRSA + ALB ingress for the real thing.

## Local (kind) — zero cost

Full platform (three services + DynamoDB Local + ElasticMQ with production DLQ
topology) on a kind cluster. E2E order flow verified twice: raw manifests
(`kind-e2e-0001`) and the helm-managed install (`helm-e2e-0001`).
`make k8s-local-up` reproduces it in one command.

## EKS — the paid hour

Stack: `infra/envs/eks-demo` — EKS 1.33, **2× t3.small/t3a.small SPOT** managed node
group, IRSA (app pods get a scoped DynamoDB+SQS role bound to their service account —
zero node-level data permissions), AWS Load Balancer Controller via its own IRSA role,
metrics-server, the makanlah chart with `ingress.enabled=true`.

Bring-up: `make demo-eks` (~26 min wall incl. controllers). Teardown: `make nuke-eks`.

### E2E through the controller-provisioned ALB

```
$ curl -X POST http://k8s-makanlah-…elb.amazonaws.com/orders -H 'Idempotency-Key: eks-e2e-0001' …
{"order_id":"eks-e2e-0001","status":"PLACED","total_rm":21,…}

notify-worker log, 77ms later:
{"message": "notification sent", "order_id": "eks-e2e-0001", …}
```

Order → ALB (ingress) → order-service pod → DynamoDB **via IRSA** → SQS → worker.

### HPA under load: 1 → 8 pods in under 2 minutes

Same k6 profile as the ECS drills (ramp to 200 VUs, 9 min), against the EKS ingress:

| Metric | ECS (validation run) | **EKS** |
|---|---|---|
| Requests | 23,162 @ 42.7/s | **77,704 @ 143.4/s** |
| Failures | 0.09% | **0.00%** |
| p95 | ramp spike → 150ms | **1.23s overall, sub-second after scale-out** |
| Scale reaction | ~6 min (CloudWatch alarm math) | **<2 min** (metrics-server 15s loop) |

HPA timeline (captured live, full log in `load/k6/results/eks-hpa-timeline.txt`):

```
14:36:51  cpu   6%/60%   1 pod
14:38:06  cpu  84%/60%   2 pods      <- first breach
14:38:44  cpu 121%/60%   6 pods      <- aggressive doubling
14:39:57  cpu 119%/60%   8 pods (max)
14:40:35+ order-service follows 1 -> 3
14:46:16  cpu   3%/60%   load ended; scale-in after the 5-min stabilization window
```

The comparison is the story: Kubernetes' HPA (15s metric loop, immediate doubling)
reacted ~3× faster than ECS CloudWatch-alarm-based target tracking. The trade: an
entire control plane you now operate (and pay $0.10/hr for) vs a managed scaler.

## Honest notes

1. **kube-prometheus-stack fight**: once its multi-MB CRDs landed, the API server's
   OpenAPI document outgrew what this workstation's link could download inside
   client timeouts — every validating kubectl/helm call then failed. Workaround:
   `--disable-openapi-validation` / `--validate=false` (charts were pre-validated
   against kind). Grafana/kube-state-metrics/node-exporter ran; the operator itself
   went Pending — see 2.
2. **Capacity math**: 2× t3.small (4 vCPU / 4GB total) fits the app *or* full
   monitoring comfortably, not both once HPA scaled to 11 app pods. A real cluster
   sizes monitoring into its own node group. Next run: 3 nodes or t3.medium.
3. Session cost: ~1h50m × ~$0.26/hr ≈ **$0.50**. Cluster destroyed the same session;
   account audited back to zero idle-billables.
