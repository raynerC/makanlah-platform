const express = require('express');
const pinoHttp = require('pino-http');
const logger = require('./logger');
const healthRoutes = require('./routes/health');
const orderRoutes = require('./routes/orders');

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use(
    pinoHttp({
      logger,
      customProps: (req, res) => ({
        method: req.method,
        path: req.url,
        status_code: res.statusCode,
      }),
    }),
  );

  app.use(healthRoutes);
  app.use(orderRoutes);

  // eslint-disable-next-line no-unused-vars -- express identifies error handlers by arity
  app.use((err, req, res, next) => {
    logger.error({ err }, 'unhandled error');
    res.status(500).json({ error: 'internal error' });
  });

  return app;
}

module.exports = { buildApp };
