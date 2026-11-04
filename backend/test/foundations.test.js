const test = require('node:test');
const assert = require('node:assert/strict');

const app = require('../src/app');
const User = require('../src/models/User');
const { parseResetArgs } = require('../seed/resetGuard');

async function withServer(run) {
  const server = app.listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('health endpoint responds', async () => {
  await withServer(async (url) => {
    const res = await fetch(`${url}/api/health`);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'ok' });
  });
});

test('unknown routes return JSON 404', async () => {
  await withServer(async (url) => {
    const res = await fetch(`${url}/api/nope`);
    assert.equal(res.status, 404);
    assert.deepEqual(await res.json(), { error: 'Not found' });
  });
});

test('--reset alone is blocked', () => {
  assert.deepEqual(parseResetArgs(['node', 'seed.js', '--reset']), { reset: false, blocked: true });
});

test('--reset with the confirmation flag is allowed', () => {
  assert.deepEqual(
    parseResetArgs(['node', 'seed.js', '--reset', '--confirm-wipe-shared-data']),
    { reset: true, blocked: false }
  );
});

test('no flags means no reset', () => {
  assert.deepEqual(parseResetArgs(['node', 'seed.js']), { reset: false, blocked: false });
});

test('the confirmation flag alone does not reset', () => {
  assert.deepEqual(
    parseResetArgs(['node', 'seed.js', '--confirm-wipe-shared-data']),
    { reset: false, blocked: false }
  );
});

test('User allows customer, vendor and admin but not student', async () => {
  const base = { name: 'A', email: 'a@b.test' };
  for (const role of ['customer', 'vendor', 'admin']) {
    await new User({ ...base, role }).validate();
  }
  await assert.rejects(new User({ ...base, role: 'student' }).validate(), /role/);
});

test('User defaults to an unverified customer and needs no password', async () => {
  const user = new User({ name: 'A', email: 'a@b.test' });
  await user.validate();
  assert.equal(user.role, 'customer');
  assert.equal(user.emailVerified, false);
});

test('User JSON never includes password or OTP fields', () => {
  const json = new User({
    name: 'A',
    email: 'a@b.test',
    passwordHash: 'hash',
    otpHash: 'hash',
    otpPurpose: 'verify_email',
    otpExpiresAt: new Date(),
    otpAttempts: 1,
  }).toJSON();

  for (const field of ['passwordHash', 'otpHash', 'otpPurpose', 'otpExpiresAt', 'otpAttempts']) {
    assert.equal(field in json, false, `${field} should be hidden`);
  }
});
