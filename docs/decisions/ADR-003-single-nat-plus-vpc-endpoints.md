# ADR-003: Single NAT Gateway + VPC Endpoints

- **Date:** 2026-07-08
- **Status:** Accepted

## Context

Fargate tasks run in private subnets across 2 AZs and need outbound access for AWS APIs.
The textbook highly-available design is one NAT gateway per AZ; NAT is also the
single most expensive line item in a small VPC.

## Decision

One NAT gateway (in the first public subnet, shared route table for all private
subnets), plus VPC endpoints for the heavy traffic: **gateway endpoints** for S3 and
DynamoDB (free) and **interface endpoints** for ECR API, ECR Docker, and CloudWatch
Logs.

## Numbers (us-east-1)

| Design | Hourly | Monthly (always-on) |
|---|---|---|
| 2× NAT (HA textbook) | $0.090 | ~$65 + $0.045/GB processing |
| 1× NAT, no endpoints | $0.045 | ~$32 + all image pulls/logs billed through NAT |
| **1× NAT + endpoints (chosen)** | $0.045 + 3×$0.01 | ~$54 worst case, but NAT processing ≈ $0 |

The interface endpoints cost $0.01/hr each but remove ECR image pulls (the largest
data mover — every task launch pulls ~50MB) and log shipping from the NAT's $0.045/GB
processing charge. S3/DynamoDB gateway endpoints are free and remove the data plane
entirely. What remains on the NAT is SQS API chatter — bytes, not gigabytes.

Since this environment only runs during work sessions (see budget cap), the practical
spend is cents per session either way; the design documents the *reasoning*, which is
what transfers to production.

## Trade-off accepted

The NAT's AZ is a single point of failure for outbound traffic from the other AZ. If
AZ-a dies, tasks in AZ-b lose the NAT path (though endpoint-routed traffic — ECR, S3,
DynamoDB, logs — survives). For dev: irrelevant. For prod: flip `az_count` NATs on with
one variable and per-AZ route tables — the module boundary already supports it.
