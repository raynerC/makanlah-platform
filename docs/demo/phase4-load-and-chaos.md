# Phase 4 evidence — load test, chaos drill, and what the telemetry caught (2026-07-12)

k6 profile: `load/k6/order-flow.js` — ramp to 200 VUs over 9 minutes, 80% browse /
20% order mix. Raw results in `load/k6/results/`.

## Drill 1 (accidental): the WAF ate the load test

First run: **98.72% of 95,087 requests blocked** with fast 403s (~175 req/s from one
IP). The WAF per-IP rate limit (500 requests / 5 min) classified the load generator as
a DoS source and shut it off — which is exactly its job. Security control validated at
no extra charge. For the real test the limit was raised temporarily via the AWS CLI
(the env is destroyed after the session; the Terraform default stays 500).

**Lesson:** load-test from multiple sources, or stage a WAF exception for the test IP.

## Drill 2: chaos — task killed at peak load

`aws ecs stop-task` on menu-service's only task at 19:08:43 UTC, mid-load:

```
19:08:43  task killed (chaos drill: task kill under load)
19:09:02  runningCount=0        ← outage window starts
19:09:26  ECS starts replacement task
19:09:55  registered with target group
19:10:04  service steady state  ← ~80s total, zero human intervention
```

![chaos recovery](img/phase4-chaos-recovery.png)

**Honest finding:** with dev's `desired_count=1`, killing the only task means ~80
seconds of 503s for that service. Self-healing works; capacity math is the fix —
prod's `desired_count=2` exists precisely for this. The `*-no-running-tasks` alarm
(2-min evaluation) did not page for an 80s gap — acceptable by design for dev.

## Drill 3: saturation — 200 VUs vs one 0.25-vCPU task

Second run (19:19–19:28 UTC), WAF out of the way:

| Metric | Value |
|---|---|
| Requests completed | 17,961 (33/s — the backend was the throttle) |
| p95 latency | **10.29s** (SLO: 800ms) |
| Failures | 26.13% — **all 4,694 were ELB-generated** (3,674 × 503), zero target 5xx |
| menu-service CPU (max) | pegged 99–100% for 8 minutes |
| Tasks | **1 the whole time — autoscaling never fired** |

![p95 latency](img/phase4-p95-latency.png)

**The alerting worked:** `makanlah-dev-p95-latency` went ALARM at 19:26:03 (SNS email
sent) and auto-recovered at 19:37:03.

**The autoscaling didn't — and the chart shows why:**

![cpu vs tasks](img/phase4-cpu-vs-tasks.png)

Target tracking scales out on *3 consecutive minutes of average CPU above target
(60%)*. The per-minute averages sawtoothed across the line (18 → 84 → 99 → 49 → 99 →
50 → 70 → 50 → 65) while max CPU sat at 100% — the single-worker service was fully
saturated but the smoothed signal kept dipping below threshold, resetting the breach
counter every other minute. Meanwhile every failure was an ELB 503 (connection
overflow to the saturated target), which the target-5xx deploy gate doesn't watch:

![elb 503](img/phase4-elb-503.png)

## Follow-ups (filed as issues, fixed, validated)

1. **Scale on `ALBRequestCountPerTarget`** (#13): request pressure is the real signal
   for a request-bound service, and it doesn't sawtooth.
2. **Add `HTTPCode_ELB_5XX_Count` to the alarm set and deploy gate** (#14): target-5xx
   catches app bugs; ELB-5xx catches saturation and no-healthy-target states.

## Validation run (2026-07-13, after the fixes)

Same 200-VU profile against the fixed environment
(request-count target tracking at 600 req/min/task, menu-service ceiling 8):

| Metric | Incident run | Validation run |
|---|---|---|
| Failures | 26.13% (4,694 ELB 503s) | **0.09%** (22) |
| menu-service tasks | 1, never scaled | **1 → 8** |
| p95 at peak | 10.3s, never recovered | 11.3s during ramp → **150ms in-SLO** after scale-out |
| Throughput | 33 req/s | 42.7 req/s |
| p95 alarm | fired, stayed until load ended | fired 05:40, **auto-recovered 05:45 as capacity arrived** |

![validation scale-out](img/phase4-validation-scaleout.png)

Timeline: single task saturates during the ramp (p95 to 11.3s, alarm fires) →
request-count policy scales 1→4 at minute 6, climbing to 8 → p95 collapses to 150ms
while 200 VUs are still running → alarm auto-recovers. The system detected and
resolved its own incident; the remaining gap is scale-out *lead time* (the ramp
outpaced the 3-minute alarm window), which is a capacity-planning knob
(min tasks / target value), not a design flaw.

The interview version: *the first load test succeeded by failing* — it proved the WAF,
the paging path, and self-healing, and caught two scaling/monitoring gaps that only
appear under real pressure. The fixes were shipped through the same PR pipeline and
validated by re-running the identical scenario.
