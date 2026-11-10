// Shared helpers for tests that call the app. Everything uses mocks; nothing reaches the shared database.
process.env.JWT_SECRET = process.env.JWT_SECRET || 'test-secret';

const app = require('../src/app');

// A resolved query that also supports .select(), like Mongoose.
function query(doc) {
  const promise = Promise.resolve(doc);
  promise.select = () => promise;
  return promise;
}

async function call(url, { method = 'GET', body, token, form } = {}) {
  const listener = app.listen(0);
  await new Promise((resolve) => listener.once('listening', resolve));
  try {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    if (!form) headers['Content-Type'] = 'application/json';
    const res = await fetch(`http://127.0.0.1:${listener.address().port}${url}`, {
      method,
      headers,
      body: form ?? (body === undefined ? undefined : JSON.stringify(body)),
    });
    return { status: res.status, body: await res.json() };
  } finally {
    listener.closeAllConnections();
    await new Promise((resolve) => listener.close(resolve));
  }
}

module.exports = { query, call };
