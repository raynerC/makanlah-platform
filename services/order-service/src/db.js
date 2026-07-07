const { DynamoDBClient, DescribeTableCommand } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  PutCommand,
  GetCommand,
} = require('@aws-sdk/lib-dynamodb');
const config = require('./config');

const client = new DynamoDBClient({
  region: config.awsRegion,
  endpoint: config.dynamodbEndpoint,
});
const doc = DynamoDBDocumentClient.from(client);

/**
 * Persist a new order. Throws ConditionalCheckFailedException when an order
 * with the same order_id already exists (the idempotent-replay case).
 */
async function createOrder(order) {
  await doc.send(
    new PutCommand({
      TableName: config.ordersTable,
      Item: order,
      ConditionExpression: 'attribute_not_exists(order_id)',
    }),
  );
  return order;
}

async function getOrder(orderId) {
  const resp = await doc.send(
    new GetCommand({
      TableName: config.ordersTable,
      Key: { order_id: orderId },
    }),
  );
  return resp.Item || null;
}

async function ping() {
  try {
    await client.send(new DescribeTableCommand({ TableName: config.ordersTable }));
    return true;
  } catch {
    return false;
  }
}

module.exports = { createOrder, getOrder, ping };
