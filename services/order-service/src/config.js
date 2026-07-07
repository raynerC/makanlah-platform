module.exports = {
  port: parseInt(process.env.PORT || '8000', 10),
  ordersTable: process.env.ORDERS_TABLE || 'orders',
  queueUrl: process.env.ORDER_EVENTS_QUEUE_URL || '',
  awsRegion: process.env.AWS_REGION || 'us-east-1',
  // set for local dev (DynamoDB Local / ElasticMQ); unset in AWS
  dynamodbEndpoint: process.env.DYNAMODB_ENDPOINT_URL || undefined,
  sqsEndpoint: process.env.SQS_ENDPOINT_URL || undefined,
  logLevel: process.env.LOG_LEVEL || 'info',
};
