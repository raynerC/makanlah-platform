# ADR-006: AWS Region Selection — us-east-1

- **Date:** 2026-07-08
- **Status:** Accepted

## Context

MakanLah's business story is Malaysian (hawker stalls), which naturally suggests
`ap-southeast-5` (Malaysia, launched 2024) or `ap-southeast-1` (Singapore). But this is a
portfolio system with no real users: the optimization targets are cost, service availability,
and learning velocity — not end-user latency.

Candidate regions considered:

| | us-east-1 | ap-southeast-1 | ap-southeast-5 |
|---|---|---|---|
| Pricing | Lowest for most services | ~10–20% higher | Similar to SG |
| Service catalog | Complete, first to get launches | Nearly complete | Limited (young region) |
| Bedrock models | Full model catalog | Partial | Restricted |
| Latency from MY | ~250ms | ~10ms | ~2ms |

## Decision

All infrastructure runs in **us-east-1**, set once as a Terraform variable
(`aws_region`) so the choice is reversible.

## Rationale

1. **Cost** — us-east-1 has the lowest unit prices for Fargate, ALB, NAT, and data transfer,
   which matters for a project with a <$15/month steady-state budget.
2. **Service and model availability** — everything this project needs (including the full
   Bedrock model catalog for Phase 6) is available without cross-region workarounds.
3. **No real users** — the ~250ms latency from Malaysia is irrelevant for demos; nothing in
   the system is latency-sensitive.

## Consequences

- The region lives in one variable; migrating means changing it, re-applying, and migrating
  data (DynamoDB export/import, ECR replication). Documented as future work.
- **Interview talking point:** in production, region choice follows user geography and data
  residency (a real Malaysian food platform would run in ap-southeast-5); for prototypes and
  PoCs, cost and service availability dominate. Knowing which regime you are in is the
  architect's job.
