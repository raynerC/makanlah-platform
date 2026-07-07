const request = require('supertest');
const { mockClient } = require('aws-sdk-client-mock');
const {
  DynamoDBDocumentClient,
  PutCommand,
  GetCommand,
} = require('@aws-sdk/lib-dynamodb');
const { ConditionalCheckFailedException } = require('@aws-sdk/client-dynamodb');
const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const { buildApp } = require('../src/app');

const ddbMock = mockClient(DynamoDBDocumentClient);
const sqsMock = mockClient(SQSClient);

const VALID_ORDER = {
  stall_id: 'stall-1',
  customer_name: 'Rayner',
  items: [
    { name: 'Nasi Lemak', qty: 2, price_rm: 6.5 },
    { name: 'Teh Tarik', qty: 1, price_rm: 2.0 },
  ],
};

let app;

beforeEach(() => {
  ddbMock.reset();
  sqsMock.reset();
  app = buildApp();
});

describe('POST /orders', () => {
  test('creates an order, computes total, publishes OrderPlaced', async () => {
    ddbMock.on(PutCommand).resolves({});
    sqsMock.on(SendMessageCommand).resolves({ MessageId: 'm-1' });

    const resp = await request(app).post('/orders').send(VALID_ORDER);

    expect(resp.status).toBe(201);
    expect(resp.body.order_id).toBeTruthy();
    expect(resp.body.status).toBe('PLACED');
    expect(resp.body.total_rm).toBe(15.0);

    const published = sqsMock.commandCalls(SendMessageCommand);
    expect(published).toHaveLength(1);
    const event = JSON.parse(published[0].args[0].input.MessageBody);
    expect(event.type).toBe('OrderPlaced');
    expect(event.order.order_id).toBe(resp.body.order_id);
  });

  test('uses Idempotency-Key as order id', async () => {
    ddbMock.on(PutCommand).resolves({});
    sqsMock.on(SendMessageCommand).resolves({});

    const resp = await request(app)
      .post('/orders')
      .set('Idempotency-Key', 'client-key-12345')
      .send(VALID_ORDER);

    expect(resp.status).toBe(201);
    expect(resp.body.order_id).toBe('client-key-12345');
  });

  test('replay with same Idempotency-Key returns existing order, no new event', async () => {
    const existing = { order_id: 'client-key-12345', status: 'PLACED', total_rm: 15.0 };
    ddbMock
      .on(PutCommand)
      .rejects(new ConditionalCheckFailedException({ $metadata: {}, message: 'exists' }));
    ddbMock.on(GetCommand).resolves({ Item: existing });

    const resp = await request(app)
      .post('/orders')
      .set('Idempotency-Key', 'client-key-12345')
      .send(VALID_ORDER);

    expect(resp.status).toBe(200);
    expect(resp.body).toEqual(existing);
    expect(sqsMock.commandCalls(SendMessageCommand)).toHaveLength(0);
  });

  test('rejects malformed Idempotency-Key', async () => {
    const resp = await request(app)
      .post('/orders')
      .set('Idempotency-Key', 'bad key!')
      .send(VALID_ORDER);
    expect(resp.status).toBe(400);
  });

  test('rejects empty items', async () => {
    const resp = await request(app)
      .post('/orders')
      .send({ ...VALID_ORDER, items: [] });
    expect(resp.status).toBe(400);
    expect(resp.body.error).toBe('invalid order');
  });

  test('rejects negative price', async () => {
    const resp = await request(app)
      .post('/orders')
      .send({ ...VALID_ORDER, items: [{ name: 'x', qty: 1, price_rm: -5 }] });
    expect(resp.status).toBe(400);
  });

  test('still returns 201 when SQS publish fails (order persisted)', async () => {
    ddbMock.on(PutCommand).resolves({});
    sqsMock.on(SendMessageCommand).rejects(new Error('sqs down'));

    const resp = await request(app).post('/orders').send(VALID_ORDER);
    expect(resp.status).toBe(201);
  });

  test('returns 500 on unexpected db error', async () => {
    ddbMock.on(PutCommand).rejects(new Error('boom'));
    const resp = await request(app).post('/orders').send(VALID_ORDER);
    expect(resp.status).toBe(500);
  });
});

describe('GET /orders/:orderId', () => {
  test('returns the order', async () => {
    const order = { order_id: 'o-1', status: 'PLACED' };
    ddbMock.on(GetCommand).resolves({ Item: order });

    const resp = await request(app).get('/orders/o-1');
    expect(resp.status).toBe(200);
    expect(resp.body).toEqual(order);
  });

  test('404 when missing', async () => {
    ddbMock.on(GetCommand).resolves({});
    const resp = await request(app).get('/orders/nope');
    expect(resp.status).toBe(404);
  });
});
