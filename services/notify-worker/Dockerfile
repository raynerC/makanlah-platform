# ---- build: install the package into a clean prefix ----
FROM python:3.13-alpine AS builder

WORKDIR /build
COPY pyproject.toml ./
COPY worker ./worker
RUN pip install --no-cache-dir --prefix=/install .

# ---- runtime: alpine base, non-root, heartbeat healthcheck ----
FROM python:3.13-alpine

RUN adduser -D -H -u 10001 appuser \
    && pip uninstall -y --quiet pip setuptools

COPY --from=builder /install /usr/local

ENV PYTHONUNBUFFERED=1

USER 10001

# workers have no HTTP port: healthy = heartbeat file touched within 60s
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import os, sys, time; sys.exit(0 if time.time() - os.path.getmtime('/tmp/notify-worker-heartbeat') < 60 else 1)"]

CMD ["python", "-m", "worker.main"]
