# order-service

Node.js (Express) service owning **order placement**. Persists orders to DynamoDB and
publishes an `OrderPlaced` event to SQS for async processing by `notify-worker`.

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/healthz` | liveness (no dependencies) |
| GET | `/readyz` | readiness (DynamoDB + SQS reachable) |
| POST | `/orders` | place an order |
| GET | `/orders/{order_id}` | fetch an order |

### Idempotency

`POST /orders` accepts an optional `Idempotency-Key` header (`[A-Za-z0-9_-]{8,64}`).
The key becomes the `order_id`, and the write is a conditional put — a retry of the same
request returns the already-created order with `200` instead of creating a duplicate,
and does **not** re-publish the event.

### Event publish failure

If the SQS publish fails after the order is persisted, the request still returns `201`
(the order exists; failing the request would not recover the event) and the failure is
logged. The proper fix is the transactional outbox pattern — future work, noted in the
architecture docs.

## Configuration (env)

| Var | Default | Notes |
|---|---|---|
| `ORDERS_TABLE` | `orders` | DynamoDB table (pk: `order_id`) |
| `ORDER_EVENTS_QUEUE_URL` | _(empty)_ | SQS queue URL |
| `AWS_REGION` | `us-east-1` | |
| `DYNAMODB_ENDPOINT_URL` / `SQS_ENDPOINT_URL` | _(unset)_ | set for local dev |
| `PORT` | `8000` | |
| `LOG_LEVEL` | `info` | pino structured JSON logs |

## Develop

```sh
npm install
npm test        # jest + supertest, aws mocked via aws-sdk-client-mock, coverage gate 80%
npm run lint
```

## Container

```sh
docker build -t makanlah/order-service .
```

Multi-stage `node:24-alpine`, production deps only, non-root `node` user, HEALTHCHECK.
