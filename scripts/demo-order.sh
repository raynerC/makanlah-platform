#!/bin/bash
# End-to-end demo against the local compose stack:
# create a stall + menu item (menu-service), place an order (order-service),
# then show the notification the worker sent for it.
set -e

MENU=http://localhost:8081
ORDER=http://localhost:8082

json_field() { # json_field <key> — extracts a string field from stdin JSON
  grep -o "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4
}

echo "=== 1. create a stall (menu-service)"
stall_json=$(curl -sf -X POST "$MENU/stalls" -H 'Content-Type: application/json' \
  -d '{"name": "Mak Cik Nasi Lemak", "cuisine": "malay", "halal": true}')
stall_id=$(echo "$stall_json" | json_field stall_id)
echo "$stall_json"

echo ""
echo "=== 2. add a menu item"
curl -sf -X POST "$MENU/stalls/$stall_id/menu" -H 'Content-Type: application/json' \
  -d '{"name": "Nasi Lemak Ayam", "price_rm": 8.5, "spicy": true}'
echo ""

echo ""
echo "=== 3. place an order (order-service, with idempotency key)"
idem_key="demo-$(date +%s)-$RANDOM"
order_json=$(curl -sf -X POST "$ORDER/orders" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $idem_key" \
  -d "{\"stall_id\": \"$stall_id\", \"customer_name\": \"Rayner\", \"items\": [{\"name\": \"Nasi Lemak Ayam\", \"qty\": 2, \"price_rm\": 8.5}]}")
order_id=$(echo "$order_json" | json_field order_id)
echo "$order_json"

echo ""
echo "=== 4. replay the same request (same key) — expect the SAME order back, no duplicate"
curl -sf -X POST "$ORDER/orders" -H 'Content-Type: application/json' \
  -H "Idempotency-Key: $idem_key" \
  -d "{\"stall_id\": \"$stall_id\", \"customer_name\": \"Rayner\", \"items\": [{\"name\": \"Nasi Lemak Ayam\", \"qty\": 2, \"price_rm\": 8.5}]}"
echo ""

echo ""
echo "=== 5. fetch the order"
curl -sf "$ORDER/orders/$order_id"
echo ""

echo ""
echo "=== 6. notification sent by notify-worker (async via SQS)"
sleep 3
docker compose logs notify-worker 2>/dev/null | grep "notification sent" | tail -2

echo ""
echo "demo complete: order $order_id flowed api -> dynamodb -> sqs -> worker."
