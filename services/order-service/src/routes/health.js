const { Router } = require('express');
const db = require('../db');
const queue = require('../queue');

const router = Router();

// liveness: process is up, no dependency checks
router.get('/healthz', (req, res) => {
  res.json({ status: 'ok' });
});

// readiness: DynamoDB table and SQS queue reachable
router.get('/readyz', async (req, res) => {
  const [dbOk, queueOk] = await Promise.all([db.ping(), queue.ping()]);
  if (dbOk && queueOk) {
    res.json({ status: 'ready' });
  } else {
    res.status(503).json({ status: 'not ready', db: dbOk, queue: queueOk });
  }
});

module.exports = router;
