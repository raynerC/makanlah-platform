# ---- deps: install production dependencies only ----
FROM node:24-alpine AS deps

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ---- runtime: bare alpine + the node binary only ----
# npm/yarn/corepack never ship to production; libstdc++ is node's one runtime dep
FROM alpine:3.22

RUN apk add --no-cache libstdc++ \
    && adduser -D -H -u 10001 appuser

COPY --from=deps /usr/local/bin/node /usr/local/bin/node

ENV NODE_ENV=production
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

USER 10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:8000/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

CMD ["node", "src/server.js"]
