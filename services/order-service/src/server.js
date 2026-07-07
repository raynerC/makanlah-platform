const config = require('./config');
const logger = require('./logger');
const { buildApp } = require('./app');

buildApp().listen(config.port, () => {
  logger.info({ port: config.port, table: config.ordersTable }, 'order-service started');
});
