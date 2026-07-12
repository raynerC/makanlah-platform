// Load profile for the MakanLah dev environment.
//
//   docker run --rm -i grafana/k6 run -e ALB=<alb-dns-name> - < load/k6/order-flow.js
//
// Ramp to 200 VUs browsing menus and placing orders. The API tasks run
// 0.25 vCPU with CPU target-tracking at 60% — this profile is sized to
// push them past the target and force a 1→N scale-out.

import http from "k6/http";
import { check, sleep } from "k6";

const BASE = `http://${__ENV.ALB}`;

export const options = {
  stages: [
    { duration: "2m", target: 50 },
    { duration: "3m", target: 200 },
    { duration: "3m", target: 200 },
    { duration: "1m", target: 0 },
  ],
  thresholds: {
    http_req_failed: ["rate<0.01"],
    "http_req_duration{kind:browse}": ["p(95)<800"],
    "http_req_duration{kind:order}": ["p(95)<800"],
  },
};

export function setup() {
  const stall = http.post(
    `${BASE}/stalls`,
    JSON.stringify({ name: "k6 Load Stall", cuisine: "mixed", halal: true }),
    { headers: { "Content-Type": "application/json" } },
  ).json();
  http.post(
    `${BASE}/stalls/${stall.stall_id}/menu`,
    JSON.stringify({ name: "Load Test Laksa", price_rm: 9.9, spicy: true }),
    { headers: { "Content-Type": "application/json" } },
  );
  return { stallId: stall.stall_id };
}

export default function (data) {
  // browse: list stalls, view the menu
  const stalls = http.get(`${BASE}/stalls`, { tags: { kind: "browse" } });
  check(stalls, { "stalls 200": (r) => r.status === 200 });
  const menu = http.get(`${BASE}/stalls/${data.stallId}/menu`, { tags: { kind: "browse" } });
  check(menu, { "menu 200": (r) => r.status === 200 });

  // roughly 1 in 5 iterations places an order
  if (Math.random() < 0.2) {
    const order = http.post(
      `${BASE}/orders`,
      JSON.stringify({
        stall_id: data.stallId,
        customer_name: "k6",
        items: [{ name: "Load Test Laksa", qty: 1, price_rm: 9.9 }],
      }),
      { headers: { "Content-Type": "application/json" }, tags: { kind: "order" } },
    );
    check(order, { "order 201": (r) => r.status === 201 });
  }

  sleep(1);
}
