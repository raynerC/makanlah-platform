# Phase 2 evidence — dev environment build, verify, destroy (2026-07-11)

Per the cost model (docs/cost.md), the dev environment exists only during work
sessions. This is the captured record of the Phase 2 acceptance run.

## Apply: zero → running platform in 5m 44s

```
Apply complete! Resources: 66 added, 0 changed, 0 destroyed.

Outputs:
alb_dns_name = "makanlah-dev-554649974.us-east-1.elb.amazonaws.com"
cluster_name = "makanlah-dev"
order_events_queue_url = "https://sqs.us-east-1.amazonaws.com/022440376627/order-events"
=== APPLY WALL TIME: 5m 44s ===
```

(+ a ~30s targeted apply of the ECR module beforehand so image pushes could precede
service creation. Acceptance gate was <20 minutes.)

## Security gates

- **tfsec**: 0 CRITICAL / 0 HIGH across `envs/dev` and `bootstrap` (6 documented
  inline suppressions with justifications; remaining findings are MEDIUM/LOW dev-tier
  choices like VPC flow logs)
- **Checkov**: 267 passed / **0 failed** (skip-list with per-check reasons in
  `.checkov.yaml`)

## End-to-end order flow over the public internet

```
$ curl -X POST http://makanlah-dev-…elb.amazonaws.com/stalls \
    -d '{"name":"Pak Din Satay","cuisine":"malay","halal":true}'
{"stall_id":"a123aedec8bd","name":"Pak Din Satay",…}

$ curl -X POST …/stalls/a123aedec8bd/menu -d '{"name":"Satay Ayam (10 stick)","price_rm":12.0,"spicy":true}'
{"item_id":"c39257413493",…}

$ curl -X POST …/orders -H 'Idempotency-Key: cloud-e2e-0001' \
    -d '{"stall_id":"a123aedec8bd","customer_name":"Rayner","items":[{"name":"Satay Ayam (10 stick)","qty":1,"price_rm":12.0}]}'
{"order_id":"cloud-e2e-0001","status":"PLACED","total_rm":12,…}          # 201

# replay with the same key: same order back, no duplicate, no second event
{"order_id":"cloud-e2e-0001",…}                                          # 200
```

Worker, from CloudWatch Logs (`/ecs/makanlah-notify-worker`) — 345ms after placement:

```
2026-07-11T15:37:06 {"message": "notification sent", "channel": "simulated-sms",
                     "order_id": "cloud-e2e-0001", "stall_id": "a123aedec8bd",
                     "total_rm": 12, "customer_name": "Rayner"}
```

Queue drained to 0 visible / 0 in-flight. Order placed over the internet flowed
ALB → order-service (Fargate, private subnet) → DynamoDB → SQS → notify-worker.

## What was running

66 resources: VPC (2 AZ, single NAT + 5 VPC endpoints), ALB + WAF (rate limit +
KnownBadInputs managed rules), ECS cluster with 3 Fargate services (autoscaling 1→4),
2 DynamoDB tables, SQS + DLQ, 3 ECR repos, least-privilege task roles per service.

## Destroy

```
Destroy complete! Resources: 72 destroyed.
=== DESTROY WALL TIME: 4m 58s ===
```

Environment destroyed the same session; `scripts/aws-audit.sh` confirmed zero
idle-billable resources afterwards. Full lifecycle (zero → live verified platform →
zero) in under 15 minutes of wall time, at a session cost of roughly **$0.10**.
