function notFound(req, res) {
  res.status(404).json({ error: 'Not found' });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  const status = err.status || err.statusCode || 500;

  if (status >= 500) {
    console.error(err);
    return res.status(status).json({ error: 'Something went wrong' });
  }

  return res.status(status).json({ error: err.message });
}

module.exports = { notFound, errorHandler };
