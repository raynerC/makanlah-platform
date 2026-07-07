# menu-service

FastAPI service owning **stalls and their menus**, backed by DynamoDB.

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/healthz` | liveness (no dependencies) |
| GET | `/readyz` | readiness (DynamoDB reachable) |
| POST | `/stalls` | create stall |
| GET | `/stalls` | list stalls |
| GET/PUT/DELETE | `/stalls/{stall_id}` | read / update / delete (cascades to menu) |
| POST | `/stalls/{stall_id}/menu` | add menu item |
| GET | `/stalls/{stall_id}/menu` | list menu |
| PUT/DELETE | `/stalls/{stall_id}/menu/{item_id}` | update / remove item |

Interactive docs at `/docs` when running.

## Data model

Single DynamoDB table (`MENUS_TABLE`, default `menus`):

```
pk = STALL#<stall_id>   sk = META            stall record
pk = STALL#<stall_id>   sk = ITEM#<item_id>  one menu item
```

A stall's entire menu is one Query. See rationale in the module docstring of `app/db.py`.

## Configuration (env)

| Var | Default | Notes |
|---|---|---|
| `MENUS_TABLE` | `menus` | DynamoDB table name |
| `AWS_REGION` | `us-east-1` | |
| `DYNAMODB_ENDPOINT_URL` | _(unset)_ | set to e.g. `http://dynamodb-local:8000` for local dev |
| `LOG_LEVEL` | `INFO` | logs are structured JSON, one object per line |

## Develop

```sh
python -m venv .venv
.venv/Scripts/pip install -e ".[dev]"   # Windows; use .venv/bin/pip on unix
.venv/Scripts/pytest                     # runs with coverage gate ≥80%
.venv/Scripts/ruff check app tests
```

Tests run against [moto](https://github.com/getmoto/moto) — no Docker or AWS needed.

## Container

Multi-stage build, non-root user, HEALTHCHECK, target <200MB:

```sh
docker build -t makanlah/menu-service .
```
