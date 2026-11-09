const { test, beforeEach, afterEach, mock } = require('node:test');
const assert = require('node:assert/strict');

const emailService = require('../src/services/emailService');

const KEYS = ['RESEND_API_KEY', 'EMAIL_FROM', 'EMAIL_REPLY_TO', 'EMAIL_USER', 'EMAIL_APP_PASSWORD'];
let saved;

beforeEach(() => {
  saved = Object.fromEntries(KEYS.map((key) => [key, process.env[key]]));
  for (const key of KEYS) delete process.env[key];
});

afterEach(() => {
  mock.restoreAll();
  for (const key of KEYS) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
});

function fakeFetch(status = 200, body = { id: 'email-id' }) {
  return mock.method(globalThis, 'fetch', async () => ({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  }));
}

test('sends through Resend when RESEND_API_KEY is set', async () => {
  process.env.RESEND_API_KEY = 're_test_key';
  process.env.EMAIL_FROM = 'SaveSpoon <no-reply@example.com>';
  process.env.EMAIL_REPLY_TO = 'support@example.com';
  const fetchMock = fakeFetch();

  await emailService.sendOtpEmail('student@example.com', 'Aisha', '380557', 'verify_email');

  assert.equal(fetchMock.mock.callCount(), 1);
  const [url, options] = fetchMock.mock.calls[0].arguments;
  assert.equal(url, 'https://api.resend.com/emails');
  assert.equal(options.method, 'POST');
  assert.equal(options.headers.Authorization, 'Bearer re_test_key');

  const body = JSON.parse(options.body);
  assert.equal(body.from, 'SaveSpoon <no-reply@example.com>');
  assert.deepEqual(body.to, ['student@example.com']);
  assert.equal(body.reply_to, 'support@example.com');
  assert.equal(body.subject, 'Email verification OTP');
  assert.match(body.text, /380557/);
  assert.match(body.html, />3<\/span>/);
});

test('leaves out reply_to when EMAIL_REPLY_TO is not set', async () => {
  process.env.RESEND_API_KEY = 're_test_key';
  process.env.EMAIL_FROM = 'SaveSpoon <no-reply@example.com>';
  const fetchMock = fakeFetch();

  await emailService.sendOtpEmail('student@example.com', 'Aisha', '380557', 'reset_password');

  const body = JSON.parse(fetchMock.mock.calls[0].arguments[1].body);
  assert.equal('reply_to' in body, false);
  assert.equal(body.subject, 'Password reset OTP');
});

test('a Resend error is thrown, so the caller reports the email as not sent', async () => {
  process.env.RESEND_API_KEY = 're_test_key';
  process.env.EMAIL_FROM = 'SaveSpoon <no-reply@example.com>';
  fakeFetch(403, { message: 'The domain is not verified.' });

  await assert.rejects(
    emailService.sendOtpEmail('student@example.com', 'Aisha', '380557', 'verify_email'),
    /Resend returned 403: The domain is not verified\./
  );
});

test('a Resend error without a message still reports the status', async () => {
  process.env.RESEND_API_KEY = 're_test_key';
  process.env.EMAIL_FROM = 'SaveSpoon <no-reply@example.com>';
  mock.method(globalThis, 'fetch', async () => ({
    ok: false,
    status: 500,
    json: async () => { throw new Error('not json'); },
  }));

  await assert.rejects(
    emailService.sendOtpEmail('student@example.com', 'Aisha', '380557', 'verify_email'),
    /^Error: Resend returned 500$/
  );
});

test('uses Gmail, not Resend, when RESEND_API_KEY is not set', async () => {
  process.env.EMAIL_USER = 'team@example.com';
  process.env.EMAIL_APP_PASSWORD = 'not-a-real-password';
  const fetchMock = fakeFetch();
  const nodemailer = require('nodemailer');
  const sendMail = mock.fn(async () => ({}));
  mock.method(nodemailer, 'createTransport', () => ({ sendMail }));

  await emailService.sendOtpEmail('student@example.com', 'Aisha', '380557', 'verify_email');

  assert.equal(fetchMock.mock.callCount(), 0);
  assert.equal(sendMail.mock.callCount(), 1);
  const message = sendMail.mock.calls[0].arguments[0];
  assert.equal(message.from, 'SaveSpoon <team@example.com>');
  assert.equal(message.to, 'student@example.com');
});
