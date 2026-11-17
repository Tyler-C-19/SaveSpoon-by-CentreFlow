const { errorAlert } = require('../services/errorAlertService');

const SERVER_ERROR = 'Something went wrong. Contact us at support@savespoon.com if it keeps happening.';

function notFound(req, res) {
  res.status(404).json({ error: 'Not found' });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  const status = err.status || err.statusCode || 500;

  if (status >= 500) {
    console.error(err);
    errorAlert(err, req, status);
    return res.status(status).json({ error: SERVER_ERROR });
  }

  return res.status(status).json({ error: err.message });
}

module.exports = { notFound, errorHandler, SERVER_ERROR };
