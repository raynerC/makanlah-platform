const crypto = require('node:crypto');
const { Router } = require('express');
const { z } = require('zod');
const { ConditionalCheckFailedException } = require('@aws-sdk/client-dynamodb');
const db = require('../db');
const queue = require('../queue');

const router = Router();

const orderSchema = z.object({
  stall_id: z.string().min(1).max(64),
  customer_name: z.string().min(1).max(100).optional(),
  items: z
    .array(
      z.object({
        name: z.string().min(1).max(100),
        qty: z.number().int().positive().max(50),
        price_rm: z.number().positive().max(1000),
      }),
    )
    .min(1)
    .max(50),
});

const IDEMPOTENCY_KEY_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;

router.post('/orders', async (req, res, next) => {
  try {
    const parsed = orderSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'invalid order', details: parsed.error.issues });
    }

    // With an Idempotency-Key header, retries of the same request map to the
    // same order_id; the conditional put turns replays into a read.
    const idempotencyKey = req.get('Idempotency-Key');
    if (idempotencyKey && !IDEMPOTENCY_KEY_PATTERN.test(idempotencyKey)) {
      return res.status(400).json({ error: 'invalid Idempotency-Key' });
    }

    const data = parsed.data;
    const totalRm =
      Math.round(data.items.reduce((sum, item) => sum + item.qty * item.price_rm, 0) * 100) / 100;
    const order = {
      order_id: idempotencyKey || crypto.randomUUID(),
      status: 'PLACED',
      total_rm: totalRm,
      created_at: new Date().toISOString(),
      ...data,
    };

    try {
      await db.createOrder(order);
    } catch (err) {
      if (err instanceof ConditionalCheckFailedException) {
        const existing = await db.getOrder(order.order_id);
        return res.status(200).json(existing);
      }
      throw err;
    }

    await queue.publishOrderPlaced(order);
    return res.status(201).json(order);
  } catch (err) {
    return next(err);
  }
});

router.get('/orders/:orderId', async (req, res, next) => {
  try {
    const order = await db.getOrder(req.params.orderId);
    if (!order) {
      return res.status(404).json({ error: 'order not found' });
    }
    return res.json(order);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
