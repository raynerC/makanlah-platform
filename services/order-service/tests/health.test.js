const request = require('supertest');
const { mockClient } = require('aws-sdk-client-mock');
const { DynamoDBClient, DescribeTableCommand } = require('@aws-sdk/client-dynamodb');
const { SQSClient, GetQueueAttributesCommand } = require('@aws-sdk/client-sqs');
const { buildApp } = require('../src/app');

const ddbMock = mockClient(DynamoDBClient);
const sqsMock = mockClient(SQSClient);

let app;

beforeEach(() => {
  ddbMock.reset();
  sqsMock.reset();
  app = buildApp();
});

test('healthz is 200 with no dependencies', async () => {
  const resp = await request(app).get('/healthz');
  expect(resp.status).toBe(200);
  expect(resp.body).toEqual({ status: 'ok' });
});

test('readyz is 200 when db and queue reachable', async () => {
  ddbMock.on(DescribeTableCommand).resolves({ Table: {} });
  sqsMock.on(GetQueueAttributesCommand).resolves({ Attributes: {} });

  const resp = await request(app).get('/readyz');
  expect(resp.status).toBe(200);
});

test('readyz is 503 when queue unreachable', async () => {
  ddbMock.on(DescribeTableCommand).resolves({ Table: {} });
  sqsMock.on(GetQueueAttributesCommand).rejects(new Error('nope'));

  const resp = await request(app).get('/readyz');
  expect(resp.status).toBe(503);
  expect(resp.body.queue).toBe(false);
});
