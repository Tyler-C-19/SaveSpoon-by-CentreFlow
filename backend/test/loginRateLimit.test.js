process.env.JWT_SECRET = 'test-secret';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const { spawnSync } = require('child_process');

const app = require('../src/app');
const { EMAIL_LIMIT } = require('../src/middleware/emailRateLimit');

async function post(server, route, ip) {
  const res = await fetch(`http://127.0.0.1:${server.address().port}/api/auth${route}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': ip },
    body: '{}',
  });
  return { status: res.status, body: await res.json(), retryAfter: res.headers.get('retry-after') };
}

async function withServer(run) {
  app.set('trust proxy', 1);
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    await run(server);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
}

test('login allows 30 requests per IP an hour, then returns 429 with a wait time', async () => {
  await withServer(async (server) => {
    for (let i = 0; i < EMAIL_LIMIT; i += 1) {
      assert.equal((await post(server, '/login', '203.0.113.20')).status, 400);
    }
    const blocked = await post(server, '/login', '203.0.113.20');
    assert.equal(blocked.status, 429);
    assert.equal(blocked.retryAfter, '3600');
    assert.equal(blocked.body.error, 'Too many requests from this network. Try again in 60 min.');
    assert.equal((await post(server, '/login', '198.51.100.20')).status, 400);
  });
});

test('the login limit and the email limit keep separate counts', async () => {
  await withServer(async (server) => {
    for (let i = 0; i < EMAIL_LIMIT; i += 1) await post(server, '/login', '203.0.113.21');
    assert.equal((await post(server, '/login', '203.0.113.21')).status, 429);
    assert.equal((await post(server, '/register', '203.0.113.21')).status, 400);

    for (let i = 0; i < EMAIL_LIMIT; i += 1) await post(server, '/forgot-password', '203.0.113.22');
    assert.equal((await post(server, '/forgot-password', '203.0.113.22')).status, 429);
    assert.equal((await post(server, '/login', '203.0.113.22')).status, 400);
  });
});

test('login requests from this computer are not counted', async () => {
  await withServer(async (server) => {
    for (let i = 0; i < EMAIL_LIMIT + 2; i += 1) {
      const res = await fetch(`http://127.0.0.1:${server.address().port}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{}',
      });
      assert.equal(res.status, 400);
    }
  });
});

test('missing settings name both places to add them, and the server stops', () => {
  const blank = ['MONGODB_URI', 'JWT_SECRET', 'RESEND_API_KEY', 'EMAIL_FROM', 'EMAIL_USER', 'EMAIL_APP_PASSWORD', 'GOOGLE_CLIENT_ID'];
  const env = { ...process.env };
  for (const key of blank) env[key] = '';

  const result = spawnSync(process.execPath, [path.join(__dirname, '..', 'src', 'server.js')], {
    env,
    encoding: 'utf8',
    timeout: 20000,
  });

  assert.equal(result.status, 1);
  assert.match(
    result.stderr,
    /Missing settings: MONGODB_URI, JWT_SECRET, EMAIL_USER, EMAIL_APP_PASSWORD, GOOGLE_CLIENT_ID\. Add them to backend\/\.env, or to the Environment tab on Render\./
  );
});
