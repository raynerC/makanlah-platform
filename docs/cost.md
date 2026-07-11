# Cost

**Budget guardrail: $5/month hard cap** (AWS Budget with email alerts at 50/80/100%
actual + 100% forecasted, created before the first `terraform apply`).

## Operating model

Nothing runs between work sessions. The dev environment exists only while being worked
on or demoed: `terraform apply` → capture evidence → `terraform destroy`. The
`scripts/aws-audit.sh` script (also `make audit`) verifies the account is back to zero
idle-billable resources after every session.

## What the dev environment costs while it exists (us-east-1)

| Component | Rate | Notes |
|---|---|---|
| ALB | $0.0225/hr + LCU | the biggest always-on lever — never left running |
| NAT gateway (single) | $0.045/hr | see ADR-003; endpoints keep processing ≈ $0 |
| Interface endpoints ×3 | $0.030/hr | save NAT processing on image pulls + logs |
| Fargate 3× (0.25 vCPU / 0.5GB) | ~$0.037/hr | scales 1→4 per service under load |
| WAF (ACL + 2 rules) | ~$0.010/hr | prorated monthly fees |
| DynamoDB / SQS / ECR / logs | ~$0 | on-demand, request-priced, tiny volumes |
| **Total** | **≈ $0.15/hour** | **a 2-hour build-demo-destroy session ≈ $0.30** |

## Steady state (what runs 24/7)

| Item | Monthly |
|---|---|
| S3 tfstate bucket (KBs) | ~$0.00 |
| ECR images (3 repos, lifecycle-capped at 10 images) | ~$0.05 |
| Budgets, IAM, OIDC provider | $0.00 |
| **Total** | **≈ $0.05/month** |

## History

- June 2026: ~$2.48 (pre-project experiments, cleaned up 2026-07-01)
- July 2026: $0.34 (July 1 residual) + ~$0.04 Cost Explorer API queries during the
  account audit; $0.00/day since
