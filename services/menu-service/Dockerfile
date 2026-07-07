# ---- build: install the package into a clean prefix ----
FROM python:3.13-alpine AS builder

WORKDIR /build
COPY pyproject.toml ./
COPY app ./app
RUN pip install --no-cache-dir --prefix=/install .

# ---- runtime: alpine base, non-root, healthchecked ----
FROM python:3.13-alpine

RUN adduser -D -H -u 10001 appuser \
    && pip uninstall -y --quiet pip setuptools

COPY --from=builder /install /usr/local

ENV PYTHONUNBUFFERED=1

USER 10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["python", "-c", "import sys, urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
