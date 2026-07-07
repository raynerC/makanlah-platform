const {
  SQSClient,
  SendMessageCommand,
  GetQueueAttributesCommand,
} = require('@aws-sdk/client-sqs');
const config = require('./config');
const logger = require('./logger');

const client = new SQSClient({
  region: config.awsRegion,
  endpoint: config.sqsEndpoint,
});

/**
 * Publish an OrderPlaced event. Failure is logged but not fatal: the order is
 * already persisted, and losing the request to a 500 would not un-lose the
 * event. The outbox pattern is the real fix — documented as future work.
 */
async function publishOrderPlaced(order) {
  try {
    await client.send(
      new SendMessageCommand({
        QueueUrl: config.queueUrl,
        MessageBody: JSON.stringify({ type: 'OrderPlaced', order }),
      }),
    );
    return true;
  } catch (err) {
    logger.error({ err, order_id: order.order_id }, 'failed to publish OrderPlaced');
    return false;
  }
}

async function ping() {
  try {
    await client.send(
      new GetQueueAttributesCommand({
        QueueUrl: config.queueUrl,
        AttributeNames: ['QueueArn'],
      }),
    );
    return true;
  } catch {
    return false;
  }
}

module.exports = { publishOrderPlaced, ping };
