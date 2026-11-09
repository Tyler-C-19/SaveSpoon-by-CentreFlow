process.env.JWT_SECRET = 'test-secret';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const app = require('../src/app');
const emailService = require('../src/services/emailService');
const { createEmailRateLimit, EMAIL_LIMIT } = require('../src/middleware/emailRateLimit');

function fakeRes() {
  return {
    statusCode: 200,
    headers: {},
    body: null,
    set(key, value) { this.headers[key] = value; return this; },
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

function run(limiter, ip) {
  const res = fakeRes();
  let passed = false;
  limiter({ ip }, res, () => { passed = true; });
  return { passed, res };
}

test('allows requests up to the limit, then returns 429 with a wait time', () => {
  const limiter = createEmailRateLimit({ limit: 3, windowMs: 60000, now: () => 0 });
  for (let i = 0; i < 3; i += 1) assert.equal(run(limiter, '203.0.113.5').passed, true);

  const { passed, res } = run(limiter, '203.0.113.5');
  assert.equal(passed, false);
  assert.equal(res.statusCode, 429);
  assert.equal(res.headers['Retry-After'], '60');
  assert.match(res.body.error, /Try again in 1 min/);
});

test('each IP address has its own count', () => {
  const limiter = createEmailRateLimit({ limit: 1, windowMs: 60000, now: () => 0 });
  assert.equal(run(limiter, '203.0.113.5').passed, true);
  assert.equal(run(limiter, '203.0.113.5').passed, false);
  assert.equal(run(limiter, '198.51.100.7').passed, true);
});

test('the count resets once the window ends', () => {
  let time = 0;
  const limiter = createEmailRateLimit({ limit: 1, windowMs: 60000, now: () => time });
  assert.equal(run(limiter, '203.0.113.5').passed, true);
  assert.equal(run(limiter, '203.0.113.5').passed, false);
  time = 60000;
  assert.equal(run(limiter, '203.0.113.5').passed, true);
});

test('requests from this computer are not counted', () => {
  const limiter = createEmailRateLimit({ limit: 1, windowMs: 60000, now: () => 0 });
  for (const ip of ['127.0.0.1', '::1', '::ffff:127.0.0.1']) {
    for (let i = 0; i < 3; i += 1) assert.equal(run(limiter, ip).passed, true);
  }
});

async function post(server, path, ip) {
  const res = await fetch(`http://127.0.0.1:${server.address().port}/api/auth${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Forwarded-For': ip },
    body: '{}',
  });
  return res.status;
}

test('register, resend and forgot password share one limit per IP; other routes are not limited', async () => {
  app.set('trust proxy', 1);
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    const paths = ['/register', '/resend-verification', '/forgot-password'];
    for (let i = 0; i < EMAIL_LIMIT; i += 1) {
      assert.equal(await post(server, paths[i % paths.length], '203.0.113.9'), 400);
    }
    for (const path of paths) assert.equal(await post(server, path, '203.0.113.9'), 429);
    assert.equal(await post(server, '/verify-email', '203.0.113.9'), 400);
    assert.equal(await post(server, '/login', '203.0.113.9'), 400);
    assert.equal(await post(server, '/register', '198.51.100.7'), 400);
  } finally {
    server.close();
  }
});

test('the OTP email keeps all six digits in one table row', () => {
  const { html } = emailService.buildOtpEmail('Aisha', '380557', 'verify_email');
  const row = html.match(/<tr><td[\s\S]*?<\/tr>/)?.[0] ?? '';
  assert.equal((row.match(/<td /g) || []).length, 6);
  assert.equal([...'380557'].every((digit) => row.includes(`>${digit}</span>`)), true);
  assert.equal(html.includes('display:inline-block'), false);
});
