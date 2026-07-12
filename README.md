# 🍜 MakanLah — Cloud-Native Food-Ordering Platform on AWS

[![ci](https://github.com/raynerC/makanlah-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/raynerC/makanlah-platform/actions/workflows/ci.yml)
[![infra](https://github.com/raynerC/makanlah-platform/actions/workflows/infra-plan.yml/badge.svg)](https://github.com/raynerC/makanlah-platform/actions/workflows/infra-plan.yml)
[![deploy](https://github.com/raynerC/makanlah-platform/actions/workflows/deploy.yml/badge.svg)](https://github.com/raynerC/makanlah-platform/actions/workflows/deploy.yml)
[![security](https://github.com/raynerC/makanlah-platform/actions/workflows/security.yml/badge.svg)](https://github.com/raynerC/makanlah-platform/actions/workflows/security.yml)

> **MakanLah** is a cloud-native food-ordering platform for Malaysian hawker stalls, built and
> operated like a production system: microservices on AWS ECS Fargate (with an EKS/Kubernetes
> deployment track), 100% Terraform-managed infrastructure, GitHub Actions CI/CD with OIDC
> (zero stored cloud credentials), full observability, DevSecOps scanning gates, and an Amazon
> Bedrock-powered AI menu assistant. Designed for high availability, least-privilege security,
> and a <$15/month steady-state AWS bill.

**Status: 🚧 Phase 4 next — observability.** Phases 0–3 complete. The platform deploys
from zero in under 6 minutes, a one-line change flows PR → merge → live with **zero
manual steps**, and a deliberately-broken deploy **auto-rolls back** (circuit breaker +
alarm watch + terraform re-pin) with the service never going dark — evidence in
[docs/demo/phase3-cicd-run.md](docs/demo/phase3-cicd-run.md) and
[docs/demo/phase2-dev-run.md](docs/demo/phase2-dev-run.md).

## Run it locally (zero AWS required)

```sh
docker compose up -d --build     # or: make up-local
bash scripts/demo-order.sh       # or: make demo-order
```

The demo creates a stall and menu item, places an order, proves idempotent replay
(same key → same order, no duplicate), and shows the notification the worker consumed
off the queue. DynamoDB Local and ElasticMQ stand in for AWS — the same code runs
unchanged against the real services via two env vars.

| Local endpoint | |
|---|---|
| menu-service | http://localhost:8081/docs |
| order-service | http://localhost:8082/healthz |
| ElasticMQ console | http://localhost:9325 |

## Target architecture

```mermaid
flowchart TB
    subgraph Internet
        U[Customer browser]
        GH[GitHub - GitHub Actions CI/CD via OIDC]
    end

    subgraph AWS["AWS us-east-1 (N. Virginia)"]
        CF[CloudFront + S3\nReact static frontend]
        WAF[AWS WAF - rate limiting]
        ALB[Application Load Balancer\nHTTPS - ACM cert]

        subgraph VPC["VPC 10.0.0.0/16 — 2 AZs"]
            subgraph Public["Public subnets"]
                NAT[NAT Gateway - single, cost-optimized]
            end
            subgraph Private["Private subnets"]
                MENU[menu-service\nFastAPI - ECS Fargate]
                ORDER[order-service\nNode.js/Express - ECS Fargate]
                WORKER[notify-worker\nPython - ECS Fargate]
            end
        end

        SQS[SQS order-events queue\n+ DLQ]
        DDB[(DynamoDB\nmenus, orders)]
        BR[Amazon Bedrock\nAI menu assistant]
        SM[Secrets Manager / SSM Parameter Store]
        ECR[ECR image registry]
        CW[CloudWatch\nlogs, dashboards, alarms - SNS email]
    end

    U --> CF
    U --> WAF --> ALB
    ALB --> MENU
    ALB --> ORDER
    ORDER -->|publish order event| SQS
    SQS --> WORKER
    MENU --> DDB
    ORDER --> DDB
    MENU -->|/ask-ai| BR
    GH -->|terraform plan/apply, docker push| ECR
    MENU & ORDER & WORKER --> CW
```

## Build phases

| Phase | Scope | Status |
|---|---|---|
| 0 | Foundations: remote state, GitHub OIDC CI roles, budget guardrails | ✅ |
| 1 | Services: menu-service (FastAPI), order-service (Node), notify-worker (Python) | ✅ |
| 2 | Core infra: VPC, ALB+WAF, ECS Fargate, DynamoDB, SQS — all Terraform | ✅ |
| 3 | CI/CD: plan-on-PR, security gates, auto-apply dev, gated prod, auto-rollback | ✅ |
| 4 | Observability: dashboards, alarms, X-Ray tracing, k6 load tests, chaos drill | ⬜ |
| 5 | Kubernetes track: kind → ephemeral EKS + Helm + HPA + Prometheus/Grafana | ⬜ |
| 6 | GenAI: Amazon Bedrock menu assistant grounded in DynamoDB data | ⬜ |
| 7 | Packaging: docs, demo video, architecture walkthrough | ⬜ |

## Security posture (from day 1)

- **Zero stored cloud credentials** — GitHub Actions authenticates to AWS via OIDC federation;
  the read-only plan role is assumable from any ref of this repo, the deploy role only from
  `main`, release tags, and gated environments
- Terraform state in a **versioned, encrypted S3 bucket** with a TLS-only bucket policy and all
  public access blocked
- **AWS Budget guardrail created before the first `terraform apply`**: $5/month with email
  alerts at 50/80/100% actual and 100% forecasted spend — environments are torn down between
  work sessions to stay under it
- Deploy role cannot touch IAM outside project-prefixed resources, and is explicitly denied
  from modifying the CI roles themselves

## Repository layout

```
├── docs/decisions/     # Architecture Decision Records
├── infra/bootstrap/    # applied once: state bucket, OIDC provider, CI roles
├── infra/modules/      # reusable Terraform modules (Phase 2+)
├── infra/envs/         # dev / prod environments (Phase 2+)
├── services/           # menu-service, order-service, notify-worker (Phase 1+)
├── frontend/           # React + Vite (Phase 2+)
└── .github/workflows/  # CI/CD pipelines
```

## Project spec

The full build spec, market research, and phase acceptance criteria live in
[AWS_CAREER_PROJECT_HANDOFF.md](AWS_CAREER_PROJECT_HANDOFF.md).
