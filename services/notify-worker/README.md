# notify-worker

Python worker consuming `OrderPlaced` events from SQS and sending (simulated) customer
notifications. The async half of the order flow: `order-service → SQS → notify-worker`.

## Poison-message handling

The worker never deletes a message that failed processing — it becomes visible again
after the visibility timeout and is retried. The **queue's redrive policy**
(`maxReceiveCount=3`, defined in Terraform with the queue) moves it to the DLQ after the
third failed receive. The worker has no DLQ logic of its own, which is the point:
failure routing is queue configuration, not application code.

## Health

No HTTP port. The worker touches a heartbeat file after every poll; the container
HEALTHCHECK fails if the file is older than 60s (hung worker, lost loop).
Graceful shutdown on SIGTERM/SIGINT (finishes the in-flight batch, then exits) —
plays nice with ECS task draining.

## Configuration (env)

| Var | Default | Notes |
|---|---|---|
| `ORDER_EVENTS_QUEUE_URL` | _(empty)_ | SQS queue URL |
| `AWS_REGION` | `us-east-1` | |
| `SQS_ENDPOINT_URL` | _(unset)_ | set for local dev (ElasticMQ) |
| `WAIT_TIME_SECONDS` | `10` | long-poll duration |
| `HEARTBEAT_FILE` | `/tmp/notify-worker-heartbeat` | |
| `LOG_LEVEL` | `INFO` | structured JSON logs |

## Develop

```sh
python -m venv .venv
.venv/Scripts/pip install -e ".[dev]"   # Windows; use .venv/bin/pip on unix
.venv/Scripts/pytest                     # moto-backed, includes a real DLQ redrive test
.venv/Scripts/ruff check worker tests
```

## Container

```sh
docker build -t makanlah/notify-worker .
```
