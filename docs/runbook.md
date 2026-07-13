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
| `*-p95-latency` | SLO breach (p95 > 800ms) | dashboard: CPU max pegged but tasks flat? CPU-average target tracking can miss saturation (see 2026-07-13 incident) — manually `aws ecs update-service --desired-count N`, then fix the scaling signal |
| `*-dlq-not-empty` | poison order events | read the DLQ message, find the worker's `message processing failed` log, fix or purge |
| `*-<svc>-no-running-tasks` | crash loop / failed deploy | `aws ecs describe-services` events, task stopped-reason, then logs |

## Incident log

### 2026-07-13 — chaos drill + saturation test (simulated)

Full evidence in [docs/demo/phase4-load-and-chaos.md](demo/phase4-load-and-chaos.md).

- **Task kill under load**: ECS self-healed in ~80s, no human action. Dev runs 1 task
  per service, so that was an 80s partial outage — prod's `desired_count=2` is the fix.
- **Saturation (200 VUs)**: p95 alarm paged correctly (19:26). Autoscaling did NOT
  fire — CPU *average* sawtoothed across the 60% target while max sat at 100%, and all
  user-facing failures were ELB 503s, invisible to the target-5xx gate. Fixed (#13
  request-count scaling, #14 ELB-5xx alarm + gate) and **validated 2026-07-13**:
  same load, 1→8 tasks, failures 26%→0.09%, p95 alarm fired and auto-recovered
  as capacity arrived.
- **Bonus**: the WAF rate limit blocked the first load run entirely (98.7% 403s) —
  security control validated by accident.
