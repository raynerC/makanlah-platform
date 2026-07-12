# Phase 3 evidence — pipeline acceptance + rollback drill (2026-07-12)

## Acceptance 1: one-line change → live in dev, zero manual steps

PR #9 changed exactly one line (menu-service API version 0.1.0 → 0.1.1):

1. PR opened → `ci` ran the menu-service suite + Trivy image scan (51s), `infra` and
   other service jobs skipped via path filters, aggregates green
2. Squash-merge → `deploy` triggered automatically (run 29193536403):
   built all three images at the merge sha, Trivy-gated, pushed to ECR via OIDC,
   `terraform apply` rolled ECS, waited for stability, watched the ALB 5xx alarm
3. Verification through the public ALB:

```
$ curl http://makanlah-dev-…elb.amazonaws.com/openapi.json | grep version
"version":"0.1.1"
```

Nothing was touched between clicking merge and the version being live.

## Acceptance 2: deliberately-broken deploy auto-rolls back

Dispatched `deploy` with `image_tag=rollback-drill-nonexistent` (run 29194884265):

```
::error::makanlah-dev-menu-service is NOT running the target tag (circuit breaker rolled it back)
::warning::deploy of 'rollback-drill-nonexistent' failed — rolling back to '4e3c40ed…'
rollback complete: dev is back on '4e3c40ed…'
```

Sequence observed:
1. Terraform pinned the bad tag; ECS tasks failed to pull the image
2. **ECS deployment circuit breaker** rolled the services back to the previous task
   definition on its own — user traffic was never routed to a broken task
3. The workflow detected the primary deployment was not running the target tag,
   **re-pinned the previous sha via terraform** (state and reality reconverge),
   waited for stability, and concluded the run as failed — a broken deploy is loud

Post-drill, with no human intervention:

```
$ curl -o /dev/null -w '%{http_code}' http://…/stalls   → 200
$ curl http://…/openapi.json | grep version             → "version":"0.1.1"
```

## Defense-in-depth summary

| Layer | Catches |
|---|---|
| PR gates (tests, Trivy, tfsec/Checkov, plan comment) | broken code/config before merge |
| ECS circuit breaker | tasks that can't start (bad image, crash loop) |
| Tag-verification step | silent circuit-breaker rollbacks — makes them fail the run |
| 10-min ALB 5xx alarm watch + terraform re-pin | code that starts fine but serves errors |

One deviation from the original spec, deliberately: PRs never push images —
pull requests only ever receive the read-only OIDC role. Images are built and
pushed from `main` by `deploy.yml`. Tighter than the spec, worth the trade.
