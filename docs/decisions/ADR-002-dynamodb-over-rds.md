# ADR-002: DynamoDB over RDS

- **Date:** 2026-07-08
- **Status:** Accepted

## Context

The platform stores two aggregates: stalls-with-menus and orders. Both are accessed by
key (stall id, order id), never by ad-hoc relational queries. The steady-state budget is
<$5/month and environments are destroyed between sessions.

## Decision

DynamoDB on-demand for both tables. Menus use a single-table layout
(`pk=STALL#<id>`, `sk=META|ITEM#<id>`) so a stall's whole menu is one Query; orders are
a simple key-value table keyed by `order_id`, which also carries the idempotency
guarantee via a conditional put.

## Rationale

1. **Access patterns are key-value.** Every production query is a GetItem/Query on a
   known key. Nothing needs joins, transactions across aggregates, or ad-hoc SQL.
2. **Cost model fits ephemeral environments.** On-demand DynamoDB costs literally $0
   when idle, spins up with `terraform apply` in seconds, and has no instance to stop.
   The smallest RDS instance (t4g.micro) is ~$12/month plus storage while it exists,
   takes ~10 minutes to provision, and bills while idle.
3. **Free-tier friendly** — 25GB storage permanently free.

## Where RDS would win (the judgment part)

- Reporting/analytics ("top dishes this month across all stalls") — DynamoDB would need
  streams into something queryable; SQL gets it for free
- Multi-item transactional invariants (inventory decrement + order create)
- A team fluent in SQL migrations and ORMs; DynamoDB single-table design has a real
  learning curve and its access patterns must be known up front

For this system those needs don't exist yet; if they arrive, the first step would be
DynamoDB Streams → a read model, not a wholesale migration.
