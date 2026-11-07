process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');

const app = require('../src/app');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const otpService = require('../src/services/otpService');
const emailService = require('../src/services/emailService');
const googleService = require('../src/services/googleService');
const { passwordError } = require('../src/validators/authValidators');

const GOOGLE = {
  googleId: 'google-123',
  email: 'Person@Example.com',
  name: 'Google Person',
  emailVerified: true,
};

let users;
let emails;
let logged;

const query = (doc) => {
  const promise = Promise.resolve(doc);
  promise.select = () => promise;
  return promise;
};

beforeEach(() => {
  mock.restoreAll();
  mock.method(Vendor, 'exists', async () => null);
  users = new Map();
  emails = [];
  logged = [];
  mock.method(User, 'findOne', ({ email, googleId }) => query(
    googleId
      ? [...users.values()].find((u) => u.googleId === googleId) ?? null
      : users.get(email) ?? null
  ));
  mock.method(googleService, 'verifyGoogleToken', async (idToken) => {
    if (idToken === 'unverified') return { ...GOOGLE, emailVerified: false };
    if (idToken !== 'good') throw new Error('bad token');
    return GOOGLE;
  });
  mock.method(User, 'findById', (id) =>
    Promise.resolve([...users.values()].find((u) => u.id === id) ?? null));
  mock.method(User.prototype, 'save', async function save() {
    users.set(this.email, this);
    return this;
  });
  mock.method(emailService, 'sendOtpEmail', async (to, name, code, purpose) => {
    emails.push({ to, name, code, purpose });
  });
  mock.method(console, 'error', (...args) => logged.push(args.join(' ')));
  mock.method(console, 'log', (...args) => logged.push(args.join(' ')));
});

async function api(method, path, body, headers = {}) {
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    const res = await fetch(`http://127.0.0.1:${server.address().port}/api/auth${path}`, {
      method,
      headers: { 'Content-Type': 'application/json', ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
}

const valid = {
  name: 'Test Person',
  email: 'Person@Example.com',
  phone: '012-3456789',
  password: 'Secret123',
  role: 'customer',
  acceptedTerms: true,
};
const EMAIL = 'person@example.com';
const lastCode = () => emails.at(-1).code;
const wrongCode = () => (lastCode() === '000000' ? '111111' : '000000');

async function registerAndVerify() {
  await api('POST', '/register', valid);
  return api('POST', '/verify-email', { email: EMAIL, code: lastCode() });
}

// Registration
test('register creates an unverified account and emails a code', async () => {
  const res = await api('POST', '/register', valid);
  assert.equal(res.status, 201);
  assert.deepEqual(res.body, { email: EMAIL, emailSent: true });
  assert.equal(users.get(EMAIL).emailVerified, false);
  assert.deepEqual(emails.map((e) => e.purpose), ['verify_email']);
  assert.equal(res.body.token, undefined);
});

test('register accepts vendor but rejects admin and creates nothing', async () => {
  assert.equal((await api('POST', '/register', { ...valid, role: 'admin' })).status, 400);
  assert.equal(users.size, 0);
  assert.equal((await api('POST', '/register', { ...valid, role: 'vendor' })).status, 201);
  assert.equal(users.get(EMAIL).role, 'vendor');
});

test('register rejects invalid input and creates nothing', async () => {
  const bad = [
    { name: ' ' },
    { email: 'nope' },
    { email: { $gt: '' } },
    { phone: 'abc' },
    { password: 'short1' },
    { password: 'lettersonly' },
    { password: '12345678' },
    { acceptedTerms: false },
  ];
  for (const change of bad) {
    const res = await api('POST', '/register', { ...valid, ...change });
    assert.equal(res.status, 400, JSON.stringify(change));
    assert.ok(res.body.error);
  }
  assert.equal(users.size, 0);
});

test('register rejects an email already in use, whatever its case', async () => {
  await api('POST', '/register', valid);
  const res = await api('POST', '/register', { ...valid, email: 'PERSON@example.com' });
  assert.equal(res.status, 409);
  assert.equal(emails.length, 1);
});

test('register still succeeds if the email fails, and the person can resend', async () => {
  emailService.sendOtpEmail.mock.mockImplementationOnce(async () => {
    throw new Error('smtp down');
  });
  const res = await api('POST', '/register', valid);
  assert.equal(res.status, 201);
  assert.equal(res.body.emailSent, false);
  assert.ok(users.get(EMAIL));
});

test('password rule enforces length and a letter and number', () => {
  assert.equal(passwordError('Secret123'), null);
  assert.ok(passwordError('Sec1'));
  assert.ok(passwordError('a1'.repeat(40)));
});

// Email code
test('the correct code verifies the account and logs the person in', async () => {
  const res = await registerAndVerify();
  assert.equal(res.status, 200);
  assert.ok(res.body.token);
  assert.equal(res.body.user.emailVerified, true);
  assert.equal(users.get(EMAIL).otpHash, undefined);
});

test('a wrong code is rejected', async () => {
  await api('POST', '/register', valid);
  const res = await api('POST', '/verify-email', { email: EMAIL, code: wrongCode() });
  assert.equal(res.status, 400);
  assert.equal(users.get(EMAIL).emailVerified, false);
});

test('the right code fails after 5 wrong attempts', async () => {
  await api('POST', '/register', valid);
  const code = lastCode();
  for (let i = 0; i < otpService.MAX_ATTEMPTS; i += 1) {
    await api('POST', '/verify-email', { email: EMAIL, code: wrongCode() });
  }
  const res = await api('POST', '/verify-email', { email: EMAIL, code });
  assert.equal(res.status, 400);
  assert.equal(users.get(EMAIL).emailVerified, false);
});

test('an expired code is rejected', async () => {
  await api('POST', '/register', valid);
  users.get(EMAIL).otpExpiresAt = new Date(Date.now() - 1000);
  const res = await api('POST', '/verify-email', { email: EMAIL, code: lastCode() });
  assert.equal(res.status, 400);
});

test('a reset code cannot verify an email', async () => {
  await api('POST', '/register', valid);
  users.get(EMAIL).otpExpiresAt = new Date(Date.now() - 2 * otpService.RESEND_COOLDOWN_MS);
  await api('POST', '/forgot-password', { email: EMAIL });
  const res = await api('POST', '/verify-email', { email: EMAIL, code: lastCode() });
  assert.equal(res.status, 400);
});

test('resend waits 60 seconds, then sends a new code', async () => {
  await api('POST', '/register', valid);
  await api('POST', '/resend-verification', { email: EMAIL });
  assert.equal(emails.length, 1);

  const user = users.get(EMAIL);
  user.otpExpiresAt = new Date(user.otpExpiresAt.getTime() - otpService.RESEND_COOLDOWN_MS);
  await api('POST', '/resend-verification', { email: EMAIL });
  assert.equal(emails.length, 2);
});

test('codes last 5 minutes', async () => {
  const before = Date.now();
  await api('POST', '/register', valid);
  const left = users.get(EMAIL).otpExpiresAt.getTime() - before;
  assert.ok(left >= 5 * 60 * 1000 && left < 5 * 60 * 1000 + 30000);
});

test('the email is addressed to the person by name', async () => {
  await api('POST', '/register', valid);
  assert.equal(emails[0].name, 'Test Person');
});

test('both emails include the name, code, expiry and warning', () => {
  for (const purpose of ['verify_email', 'reset_password']) {
    const { subject, text, html } = emailService.buildOtpEmail('Aisha', '380557', purpose);
    assert.match(subject, /OTP/);
    assert.match(text, /Hi Aisha,/);
    assert.match(text, /Your OTP is: 380557/);
    assert.match(text, /next 5 minutes/);
    assert.match(text, /Do not share it/);
    assert.match(html, /Hi Aisha,/);
    assert.match(html, /Code requested/);
    assert.equal([...'380557'].every((digit) => html.includes(`>${digit}</span>`)), true);
  }
});

test('a name cannot add HTML to the email', () => {
  const { html } = emailService.buildOtpEmail('<img src=x onerror=y>', '123456', 'verify_email');
  assert.equal(html.includes('<img'), false);
  assert.ok(html.includes('&lt;img'));
});

test('generated codes are always 6 digits', () => {
  for (let i = 0; i < 200; i += 1) {
    assert.match(otpService.generateCode(), /^[0-9]{6}$/);
  }
});

// Login
test('a verified user can log in', async () => {
  await registerAndVerify();
  const res = await api('POST', '/login', { email: 'PERSON@example.com', password: valid.password });
  assert.equal(res.status, 200);
  assert.ok(res.body.token);
});

test('wrong password and unknown email give the same error', async () => {
  await registerAndVerify();
  const wrong = await api('POST', '/login', { email: EMAIL, password: 'Wrong1234' });
  const unknown = await api('POST', '/login', { email: 'no@one.com', password: 'Wrong1234' });
  assert.equal(wrong.status, 401);
  assert.deepEqual(wrong, unknown);
});

test('login ignores non-text values', async () => {
  const res = await api('POST', '/login', { email: { $gt: '' }, password: { $gt: '' } });
  assert.equal(res.status, 400);
});

test('an unverified user with the right password is sent to verify', async () => {
  await api('POST', '/register', valid);
  const res = await api('POST', '/login', { email: EMAIL, password: valid.password });
  assert.equal(res.status, 403);
  assert.equal(res.body.code, 'EMAIL_NOT_VERIFIED');
  assert.equal(res.body.token, undefined);
});

test('an unverified user with the wrong password gets the generic error', async () => {
  await api('POST', '/register', valid);
  const res = await api('POST', '/login', { email: EMAIL, password: 'Wrong1234' });
  assert.equal(res.status, 401);
});

// Password reset
test('reset emails a code and sets a new password', async () => {
  await registerAndVerify();
  const user = users.get(EMAIL);
  user.otpExpiresAt = undefined;
  await api('POST', '/forgot-password', { email: EMAIL });
  assert.equal(emails.at(-1).purpose, 'reset_password');

  const newPassword = 'NewSecret456';
  const res = await api('POST', '/reset-password', { email: EMAIL, code: lastCode(), newPassword });
  assert.equal(res.status, 200);
  assert.equal((await api('POST', '/login', { email: EMAIL, password: valid.password })).status, 401);
  assert.equal((await api('POST', '/login', { email: EMAIL, password: newPassword })).status, 200);
});

test('forgot password responds the same whether or not the email exists', async () => {
  await registerAndVerify();
  users.get(EMAIL).otpExpiresAt = undefined;
  const known = await api('POST', '/forgot-password', { email: EMAIL });
  const unknown = await api('POST', '/forgot-password', { email: 'no@one.com' });
  assert.deepEqual(known, unknown);
  assert.equal(emails.filter((e) => e.to === 'no@one.com').length, 0);
});

test('reset rejects a weak password and a wrong code', async () => {
  await registerAndVerify();
  users.get(EMAIL).otpExpiresAt = undefined;
  await api('POST', '/forgot-password', { email: EMAIL });
  const weak = await api('POST', '/reset-password', { email: EMAIL, code: lastCode(), newPassword: 'weak' });
  assert.equal(weak.status, 400);
  const wrong = await api('POST', '/reset-password', { email: EMAIL, code: wrongCode(), newPassword: 'NewSecret456' });
  assert.equal(wrong.status, 400);
});

// Google sign-in
const googleProfile = { idToken: 'good', role: 'vendor', phone: '012-3456789', acceptedTerms: true };

test('a first-time Google user is asked for their details, with no account yet', async () => {
  const res = await api('POST', '/google', { idToken: 'good' });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { needsProfile: true, email: EMAIL, name: 'Google Person' });
  assert.equal(users.size, 0);
});

test('finishing Google sign-up creates a verified account with no password', async () => {
  const res = await api('POST', '/google/complete', googleProfile);
  assert.equal(res.status, 201);
  assert.ok(res.body.token);
  const user = users.get(EMAIL);
  assert.equal(user.role, 'vendor');
  assert.equal(user.phone, '012-3456789');
  assert.equal(user.googleId, 'google-123');
  assert.equal(user.emailVerified, true);
  assert.equal(user.passwordHash, undefined);
  assert.equal(emails.length, 0);
});

test('finishing Google sign-up requires a role, phone and Terms, and rejects admin', async () => {
  const bad = [{ role: 'admin' }, { role: undefined }, { phone: 'abc' }, { acceptedTerms: false }];
  for (const change of bad) {
    const res = await api('POST', '/google/complete', { ...googleProfile, ...change });
    assert.equal(res.status, 400, JSON.stringify(change));
  }
  assert.equal(users.size, 0);
});

test('a returning Google user logs straight in', async () => {
  await api('POST', '/google/complete', googleProfile);
  const res = await api('POST', '/google', { idToken: 'good' });
  assert.equal(res.status, 200);
  assert.ok(res.body.token);
  assert.equal(res.body.needsProfile, undefined);
});

test('forged, missing and unverified Google tokens are rejected', async () => {
  for (const idToken of ['forged', undefined, { $gt: '' }, 'unverified']) {
    assert.equal((await api('POST', '/google', { idToken })).status, 401);
  }
  const res = await api('POST', '/google/complete', { ...googleProfile, idToken: 'forged' });
  assert.equal(res.status, 401);
  assert.equal(users.size, 0);
});

test('Google links to a verified account and keeps its password', async () => {
  await registerAndVerify();
  const res = await api('POST', '/google', { idToken: 'good' });
  assert.equal(res.status, 200);
  assert.ok(res.body.token);
  assert.equal(users.get(EMAIL).googleId, 'google-123');
  const login = await api('POST', '/login', { email: EMAIL, password: valid.password });
  assert.equal(login.status, 200);
});

test('Google removes the password from an unverified account with that email', async () => {
  await api('POST', '/register', valid);
  const res = await api('POST', '/google', { idToken: 'good' });
  assert.equal(res.status, 200);
  const user = users.get(EMAIL);
  assert.equal(user.emailVerified, true);
  assert.equal(user.passwordHash, undefined);
  const login = await api('POST', '/login', { email: EMAIL, password: valid.password });
  assert.equal(login.status, 401);
});

test('a Google-only account cannot log in with a password but can set one by reset', async () => {
  await api('POST', '/google/complete', googleProfile);
  const denied = await api('POST', '/login', { email: EMAIL, password: 'Anything123' });
  assert.equal(denied.status, 401);

  await api('POST', '/forgot-password', { email: EMAIL });
  await api('POST', '/reset-password', { email: EMAIL, code: lastCode(), newPassword: 'NewSecret456' });
  const login = await api('POST', '/login', { email: EMAIL, password: 'NewSecret456' });
  assert.equal(login.status, 200);
});

test('Google responses never include secrets', async () => {
  await api('POST', '/register', valid);
  const res = await api('POST', '/google', { idToken: 'good' });
  const text = JSON.stringify(res.body);
  for (const secret of ['passwordHash', 'otpHash', 'otpExpiresAt']) {
    assert.equal(text.includes(secret), false, secret);
  }
});

// Sessions and secrets
test('responses and logs never include passwords, hashes or codes', async () => {
  const res = await registerAndVerify();
  const text = JSON.stringify(res.body);
  for (const secret of ['passwordHash', 'otpHash', 'otpExpiresAt', 'otpAttempts', 'otpPurpose', valid.password]) {
    assert.equal(text.includes(secret), false, secret);
  }
  const logs = logged.join('\n');
  assert.equal(logs.includes(valid.password), false);
  assert.equal(logs.includes(emails[0].code), false);
});

test('passwords and codes are stored only as hashes', async () => {
  await api('POST', '/register', valid);
  const user = users.get(EMAIL);
  assert.notEqual(user.passwordHash, valid.password);
  assert.notEqual(user.otpHash, lastCode());
});

test('the token lasts 7 days', async () => {
  const { body } = await registerAndVerify();
  const { iat, exp, sub } = jwt.decode(body.token);
  assert.equal(exp - iat, 7 * 24 * 60 * 60);
  assert.equal(sub, users.get(EMAIL).id);
});

test('/me returns the user for a valid token', async () => {
  const { body } = await registerAndVerify();
  const res = await api('GET', '/me', undefined, { Authorization: `Bearer ${body.token}` });
  assert.equal(res.status, 200);
  assert.equal(res.body.user.email, EMAIL);
});

test('/me rejects missing, expired and forged tokens', async () => {
  const { body } = await registerAndVerify();
  const { sub } = jwt.decode(body.token);
  const expired = jwt.sign({}, process.env.JWT_SECRET, { subject: sub, expiresIn: -10 });
  const forged = jwt.sign({}, 'another-secret', { subject: sub });

  assert.equal((await api('GET', '/me')).status, 401);
  for (const token of [expired, forged, 'junk']) {
    const res = await api('GET', '/me', undefined, { Authorization: `Bearer ${token}` });
    assert.equal(res.status, 401);
  }
});

test('/me rejects a token for a deleted user', async () => {
  const { body } = await registerAndVerify();
  users.clear();
  const res = await api('GET', '/me', undefined, { Authorization: `Bearer ${body.token}` });
  assert.equal(res.status, 401);
});

test('malformed JSON gets a 400, not a crash', async () => {
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    const res = await fetch(`http://127.0.0.1:${server.address().port}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{bad',
    });
    assert.equal(res.status, 400);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});
