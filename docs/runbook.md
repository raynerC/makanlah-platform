# Runbook

## Deploy

Merges to `main` deploy automatically when `DEV_ENV_ENABLED=true` (repo variable):
build → Trivy → push sha images → `terraform apply` → ECS stability gate → 10-min
ALB 5xx alarm watch. Manual deploy / redeploy of any existing tag:

```
gh workflow run deploy -f image_tag=<sha>        # omit to build HEAD
```

## Rollback

Automatic: a deploy that fails ECS stabilization (circuit breaker) or trips the
5xx alarm within the watch window is rolled back to the previous tag by the
workflow itself. Manual rollback = redeploy the last good sha (see above; the
previous tag is in the failed run's "Resolve target + previous tags" step).

## Bring the environment up / tear it down

```
gh api -X PATCH repos/raynerC/makanlah-platform/actions/variables/DEV_ENV_ENABLED -f name=DEV_ENV_ENABLED -f value=true
gh workflow run deploy                            # up (~15 min to verified)

make nuke                                         # down (local compose + terraform destroy)
gh api -X PATCH .../DEV_ENV_ENABLED ... -f value=false
make audit                                        # verify account is at zero
```

## Alarm response

| Alarm | Meaning | First moves |
|---|---|---|
| `*-alb-target-5xx` | backends returning errors | recent deploy? → rollback. `aws logs tail /ecs/makanlah-dev-<svc> --since 15m` for stack traces |
| `*-p95-latency` | SLO breach (p95 > 800ms) | dashboard: CPU pegged? → autoscaling should react; not scaling → check max_count ceiling |
| `*-dlq-not-empty` | poison order events | read the DLQ message, find the worker's `message processing failed` log, fix or purge |
| `*-<svc>-no-running-tasks` | crash loop / failed deploy | `aws ecs describe-services` events, task stopped-reason, then logs |

## Incident log

### 2026-07-13 — chaos drill: task kill under load (simulated)

Recorded in [docs/demo/phase4-load-and-chaos.md](demo/phase4-load-and-chaos.md).
