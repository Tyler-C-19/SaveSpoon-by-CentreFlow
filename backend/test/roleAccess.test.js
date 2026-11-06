// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const bcrypt = require('bcryptjs');
const express = require('express');

const app = require('../src/app');
const User = require('../src/models/User');
const googleService = require('../src/services/googleService');
const { requireRole } = require('../src/middleware/auth');
const { signToken } = require('../src/services/tokenService');
const { createAdmin, removeDefaultAdmin, DEFAULT_ADMIN } = require('../scripts/createAdmin');

const PASSWORD = 'Secret123';
const passwordHash = bcrypt.hashSync(PASSWORD, 4);

const query = (doc) => {
  const promise = Promise.resolve(doc);
  promise.select = () => promise;
  return promise;
};

const makeUser = (role, fields = {}) => new User({
  name: 'Test', email: `${role}@example.com`, role, passwordHash, emailVerified: true, ...fields,
});

beforeEach(() => mock.restoreAll());

async function call(server, url, { method = 'GET', body, token } = {}) {
  const listener = server.listen(0);
  await new Promise((resolve) => listener.once('listening', resolve));
  try {
    const res = await fetch(`http://127.0.0.1:${listener.address().port}${url}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  } finally {
    listener.closeAllConnections();
    await new Promise((resolve) => listener.close(resolve));
  }
}

function vendorOnlyApp() {
  const server = express();
  server.get('/vendor-only', requireRole('vendor'), (req, res) => res.json({ ok: true }));
  server.get('/shared', requireRole('vendor', 'admin'), (req, res) => res.json({ ok: true }));
  return server;
}

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

// AC1: role check

test('requireRole returns 401 when not logged in', async () => {
  const res = await call(vendorOnlyApp(), '/vendor-only');
  assert.equal(res.status, 401);
});

test('requireRole returns 401 for a bad token', async () => {
  const res = await call(vendorOnlyApp(), '/vendor-only', { token: 'not-a-token' });
  assert.equal(res.status, 401);
});

test('requireRole returns 403 for the wrong role', async () => {
  for (const role of ['customer', 'admin']) {
    const token = signedInAs(makeUser(role));
    const res = await call(vendorOnlyApp(), '/vendor-only', { token });
    assert.equal(res.status, 403, role);
    mock.restoreAll();
  }
});

test('requireRole lets the right role through', async () => {
  const token = signedInAs(makeUser('vendor'));
  const res = await call(vendorOnlyApp(), '/vendor-only', { token });
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { ok: true });
});

test('requireRole accepts any of several roles', async () => {
  const token = signedInAs(makeUser('admin'));
  const res = await call(vendorOnlyApp(), '/shared', { token });
  assert.equal(res.status, 200);
});

test('requireRole uses the current role, not the one at login', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  user.role = 'customer';
  const res = await call(vendorOnlyApp(), '/vendor-only', { token });
  assert.equal(res.status, 403);
});

// AC3: admins are blocked from mobile sign-in

test('an admin with the right password gets 403 and no token', async () => {
  const admin = makeUser('admin');
  mock.method(User, 'findOne', () => query(admin));
  const res = await call(app, '/api/auth/login', {
    method: 'POST',
    body: { email: admin.email, password: PASSWORD },
  });
  assert.equal(res.status, 403);
  assert.equal(res.body.code, 'ADMIN_USE_DASHBOARD');
  assert.equal('token' in res.body, false);
});

test('an admin with the wrong password gets the normal login error', async () => {
  const admin = makeUser('admin');
  mock.method(User, 'findOne', () => query(admin));
  const res = await call(app, '/api/auth/login', {
    method: 'POST',
    body: { email: admin.email, password: 'Wrong1234' },
  });
  assert.equal(res.status, 401);
  assert.equal(res.body.code, undefined);
});

test('customers and vendors still log in', async () => {
  for (const role of ['customer', 'vendor']) {
    const user = makeUser(role);
    mock.method(User, 'findOne', () => query(user));
    const res = await call(app, '/api/auth/login', {
      method: 'POST',
      body: { email: user.email, password: PASSWORD },
    });
    assert.equal(res.status, 200, role);
    assert.ok(res.body.token, role);
    mock.restoreAll();
  }
});

for (const [route, body] of [
  ['/api/auth/google', { idToken: 'good' }],
  ['/api/auth/google/complete', {
    idToken: 'good', role: 'customer', phone: '012-3456789', acceptedTerms: true,
  }],
]) {
  test(`${route} blocks an admin without linking Google`, async () => {
    const admin = makeUser('admin');
    const save = mock.method(User.prototype, 'save', async function save() { return this; });
    mock.method(User, 'findOne', ({ email }) => query(email ? admin : null));
    mock.method(googleService, 'verifyGoogleToken', async () => ({
      googleId: 'google-1', email: admin.email, name: 'Admin', emailVerified: true,
    }));

    const res = await call(app, route, { method: 'POST', body });

    assert.equal(res.status, 403);
    assert.equal(res.body.code, 'ADMIN_USE_DASHBOARD');
    assert.equal('token' in res.body, false);
    assert.equal(admin.googleId, undefined);
    assert.equal(save.mock.callCount(), 0);
  });
}

// AC4: create-admin script

const details = { email: 'Boss@Example.com', password: PASSWORD };

test('createAdmin stores a verified admin with only a password hash', async () => {
  mock.method(User, 'findOne', () => query(null));
  const create = mock.method(User, 'create', async (doc) => doc);

  assert.equal(await createAdmin(details), true);

  const doc = create.mock.calls[0].arguments[0];
  assert.equal(doc.email, 'boss@example.com');
  assert.equal(doc.role, 'admin');
  assert.equal(doc.emailVerified, true);
  assert.equal('password' in doc, false);
  assert.notEqual(doc.passwordHash, PASSWORD);
  assert.equal(await bcrypt.compare(PASSWORD, doc.passwordHash), true);
});

test('createAdmin changes nothing when the admin already exists', async () => {
  const admin = makeUser('admin', { email: 'boss@example.com' });
  const before = admin.passwordHash;
  mock.method(User, 'findOne', () => query(admin));
  const create = mock.method(User, 'create', async (doc) => doc);
  const save = mock.method(User.prototype, 'save', async function save() { return this; });

  assert.equal(await createAdmin(details), false);

  assert.equal(create.mock.callCount(), 0);
  assert.equal(save.mock.callCount(), 0);
  assert.equal(admin.passwordHash, before);
});

test('createAdmin refuses an email that belongs to a non-admin', async () => {
  mock.method(User, 'findOne', () => query(makeUser('vendor')));
  const create = mock.method(User, 'create', async (doc) => doc);

  await assert.rejects(createAdmin(details), /vendor account/);
  assert.equal(create.mock.callCount(), 0);
});

test('createAdmin applies the password rule and refuses the default email', async () => {
  const findOne = mock.method(User, 'findOne', () => query(null));
  await assert.rejects(createAdmin({ email: 'boss@example.com', password: 'short1' }), /ADMIN_PASSWORD/);
  await assert.rejects(createAdmin({ email: 'nope', password: PASSWORD }), /ADMIN_EMAIL/);
  await assert.rejects(createAdmin({ email: DEFAULT_ADMIN, password: PASSWORD }), /ADMIN_EMAIL/);
  assert.equal(findOne.mock.callCount(), 0);
});

test('removeDefaultAdmin targets only the default admin account', async () => {
  const deleteOne = mock.method(User, 'deleteOne', async () => ({ deletedCount: 1 }));
  assert.equal(await removeDefaultAdmin(), true);
  assert.deepEqual(deleteOne.mock.calls[0].arguments[0], { email: DEFAULT_ADMIN, role: 'admin' });
});

// AC5: seed

test('the seed creates no admin and keeps admins on reset', () => {
  const seed = fs.readFileSync(path.join(__dirname, '..', 'seed', 'seed.js'), 'utf8');
  assert.doesNotMatch(seed, /role: 'admin'/);
  assert.doesNotMatch(seed, /admin@savespoon/);
  assert.match(seed, /User\.deleteMany\(seededUsers\)/);
  assert.equal((seed.match(/account\(\{/g) ?? []).length, 5);
});
