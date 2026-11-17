const { test, beforeEach, afterEach, mock } = require('node:test');
const assert = require('node:assert/strict');

const emailService = require('../src/services/emailService');
const { createErrorAlert } = require('../src/services/errorAlertService');
const { errorHandler, SERVER_ERROR } = require('../src/middleware/errorHandler');

const KEYS = ['RENDER', 'EMAIL_REPLY_TO'];
let saved;

beforeEach(() => {
  saved = Object.fromEntries(KEYS.map((key) => [key, process.env[key]]));
  process.env.RENDER = 'true';
  process.env.EMAIL_REPLY_TO = 'support@example.com';
});

afterEach(() => {
  mock.restoreAll();
  for (const key of KEYS) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
});

function fakeReq(overrides = {}) {
  return {
    method: 'GET',
    baseUrl: '/api/listings',
    route: { path: '/search' },
    originalUrl: '/api/listings/search?q=nasi+lemak',
    query: { q: 'nasi lemak' },
    headers: { authorization: 'Bearer secret-token-123' },
    body: { password: 'Secret123', code: '380557' },
    ...overrides,
  };
}

function fakeRes() {
  return {
    statusCode: 200,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}

test('on Render, emails EMAIL_REPLY_TO with the route pattern, status and error', async () => {
  const send = mock.fn(async () => {});
  const alert = createErrorAlert({ send, now: () => Date.UTC(2026, 10, 9, 6, 0) });

  assert.equal(await alert(new TypeError('price is undefined'), fakeReq(), 500), true);

  assert.equal(send.mock.callCount(), 1);
  const [to, subject, text] = send.mock.calls[0].arguments;
  assert.equal(to, 'support@example.com');
  assert.equal(subject, 'SaveSpoon server error: 500 on GET /api/listings/search');
  assert.match(text, /Time: 09\/11\/2026, 14:00:00 \(MYT\)/);
  assert.match(text, /Status: 500/);
  assert.match(text, /Error: TypeError: price is undefined/);
  assert.match(text, /Trace:\n {2}at /);
});

test('never includes the request contents, token, password, code or search text', async () => {
  const send = mock.fn(async () => {});
  const alert = createErrorAlert({ send });

  await alert(new Error('boom'), fakeReq(), 500);

  const [, subject, text] = send.mock.calls[0].arguments;
  for (const secret of ['secret-token-123', 'Secret123', '380557', 'nasi', '?q=']) {
    assert.equal(subject.includes(secret), false, secret);
    assert.equal(text.includes(secret), false, secret);
  }
});

test('sends nothing off Render or without EMAIL_REPLY_TO', async () => {
  const send = mock.fn(async () => {});
  const alert = createErrorAlert({ send });

  delete process.env.RENDER;
  assert.equal(await alert(new Error('boom'), fakeReq(), 500), false);
  process.env.RENDER = 'true';
  delete process.env.EMAIL_REPLY_TO;
  assert.equal(await alert(new Error('boom'), fakeReq(), 500), false);

  assert.equal(send.mock.callCount(), 0);
});

test('the same error on the same route is emailed at most once an hour', async () => {
  let time = 0;
  const send = mock.fn(async () => {});
  const alert = createErrorAlert({ send, now: () => time });

  assert.equal(await alert(new Error('boom'), fakeReq(), 500), true);
  time = 59 * 60 * 1000;
  assert.equal(await alert(new Error('boom'), fakeReq(), 500), false);
  assert.equal(await alert(new Error('other'), fakeReq(), 500), true);
  assert.equal(await alert(new Error('boom'), fakeReq({ route: { path: '/:id' } }), 500), true);
  time = 60 * 60 * 1000;
  assert.equal(await alert(new Error('boom'), fakeReq(), 500), true);

  assert.equal(send.mock.callCount(), 4);
});

test('a failed alert email is logged and never thrown', async () => {
  const logged = mock.method(console, 'error', () => {});
  const alert = createErrorAlert({ send: async () => { throw new Error('Resend returned 500'); } });

  assert.equal(await alert(new Error('boom'), fakeReq(), 500), false);
  assert.match(logged.mock.calls[0].arguments.join(' '), /Could not send error alert: Resend returned 500/);
});

test('a request with no matching route is still reported without its address', async () => {
  const send = mock.fn(async () => {});
  const alert = createErrorAlert({ send });

  await alert(new Error('boom'), fakeReq({ route: undefined, baseUrl: '' }), 503);

  assert.equal(send.mock.calls[0].arguments[1], 'SaveSpoon server error: 503 on GET (no matching route)');
});

test('the error handler answers server errors with the support message and sends one alert', async () => {
  mock.method(console, 'error', () => {});
  const sendAlert = mock.method(emailService, 'sendAlertEmail', async () => {});

  const res = fakeRes();
  errorHandler(new Error('handler boom'), fakeReq({ method: 'POST', baseUrl: '/api/orders', route: { path: '/' } }), res, () => {});
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(res.statusCode, 500);
  assert.deepEqual(res.body, { error: SERVER_ERROR });
  assert.equal(SERVER_ERROR, 'Something went wrong. Contact us at support@savespoon.com if it keeps happening.');
  assert.equal(sendAlert.mock.callCount(), 1);
  assert.equal(sendAlert.mock.calls[0].arguments[1], 'SaveSpoon server error: 500 on POST /api/orders/');
});

test('client errors keep their own message and send no alert', () => {
  const sendAlert = mock.method(emailService, 'sendAlertEmail', async () => {});
  const err = Object.assign(new Error('Choose a valid quantity.'), { status: 400 });

  const res = fakeRes();
  errorHandler(err, fakeReq(), res, () => {});

  assert.equal(res.statusCode, 400);
  assert.deepEqual(res.body, { error: 'Choose a valid quantity.' });
  assert.equal(sendAlert.mock.callCount(), 0);
});

test('the alert email goes out through the normal email sender as plain text', async () => {
  const savedKeys = { key: process.env.RESEND_API_KEY, from: process.env.EMAIL_FROM };
  process.env.RESEND_API_KEY = 're_test_key';
  process.env.EMAIL_FROM = 'SaveSpoon <no-reply@example.com>';
  const fetchMock = mock.method(globalThis, 'fetch', async () => ({ ok: true, status: 200, json: async () => ({}) }));
  try {
    await emailService.sendAlertEmail('support@example.com', 'Subject line', 'Body text');
    const body = JSON.parse(fetchMock.mock.calls[0].arguments[1].body);
    assert.deepEqual(body.to, ['support@example.com']);
    assert.equal(body.subject, 'Subject line');
    assert.equal(body.text, 'Body text');
    assert.equal('html' in body, false);
  } finally {
    if (savedKeys.key === undefined) delete process.env.RESEND_API_KEY;
    else process.env.RESEND_API_KEY = savedKeys.key;
    if (savedKeys.from === undefined) delete process.env.EMAIL_FROM;
    else process.env.EMAIL_FROM = savedKeys.from;
  }
});
