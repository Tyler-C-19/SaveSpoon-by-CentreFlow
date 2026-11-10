// These tests replace database and email calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const emailService = require('../src/services/emailService');
const { signToken } = require('../src/services/tokenService');

const PASSWORD = 'oldpass123';
const HASH = bcrypt.hashSync(PASSWORD, 4);

let emails;
let saved;

function makeUser(role = 'customer', extra = {}) {
  return new User({
    name: 'Test Person', email: `${role}@example.com`, phone: '012-3456789', role, emailVerified: true, ...extra,
  });
}

// Signs in as the user; findById returns the same document every time.
function signedInAs(user) {
  mock.method(User, 'findById', () => query(user));
  mock.method(User, 'exists', async ({ passwordHash, email }) => {
    if (passwordHash) return user.passwordHash ? { _id: user._id } : null;
    if (email) return email === 'taken@example.com' ? { _id: 'other' } : null;
    return null;
  });
  return signToken(user.id);
}

beforeEach(() => {
  mock.restoreAll();
  emails = [];
  saved = 0;
  mock.method(User.prototype, 'save', async function save() {
    saved += 1;
    return this;
  });
  mock.method(Vendor, 'findOne', async () => null);
  mock.method(emailService, 'sendOtpEmail', async (to, name, code, purpose) => emails.push({ to, code, purpose }));
  mock.method(emailService, 'sendPasswordChangedEmail', async (to) => emails.push({ to, purpose: 'password_changed' }));
  mock.method(emailService, 'sendEmailChangedEmail', async (to, name, newEmail) =>
    emails.push({ to, newEmail, purpose: 'email_changed' }));
  mock.method(console, 'error', () => {});
});

// Access

for (const [method, url] of [
  ['GET', '/api/users/me'],
  ['PATCH', '/api/users/me'],
  ['DELETE', '/api/users/me'],
  ['GET', '/api/users/me/summary'],
  ['POST', '/api/users/me/password'],
  ['POST', '/api/users/me/email'],
  ['POST', '/api/users/me/email/resend'],
  ['POST', '/api/users/me/email/verify'],
  ['PUT', '/api/users/me/photo'],
  ['PATCH', '/api/users/me/photo'],
  ['DELETE', '/api/users/me/email'],
  ['DELETE', '/api/users/me/photo'],
]) {
  test(`${method} ${url} returns 401 when logged out and 403 for admins`, async () => {
    assert.equal((await call(url, { method })).status, 401);
    const token = signedInAs(makeUser('admin'));
    assert.equal((await call(url, { method, token })).status, 403);
  });
}

// AC1: profile

test('GET returns the profile without secrets, with password and Google flags', async () => {
  const user = makeUser('customer', { passwordHash: HASH, googleId: 'g-1', otpHash: 'x', pendingEmail: 'a@b.co' });
  const token = signedInAs(user);

  const res = await call('/api/users/me', { token });

  assert.equal(res.status, 200);
  assert.equal(res.body.user.name, 'Test Person');
  assert.equal(res.body.user.hasPassword, true);
  assert.equal(res.body.user.isGoogleLinked, true);
  for (const field of ['passwordHash', 'otpHash', 'pendingEmail', 'passwordChangedAt', 'photoId']) {
    assert.equal(field in res.body.user, false, field);
  }
});

test('names with numbers or symbols are accepted', async () => {
  for (const name of ['Tan Li Jia', 'Ali 2', "O'Brien", '李佳']) {
    const token = signedInAs(makeUser());
    const res = await call('/api/users/me', { method: 'PATCH', token, body: { name } });
    assert.equal(res.status, 200, name);
    mock.restoreAll();
    mock.method(User.prototype, 'save', async function save() { return this; });
    mock.method(Vendor, 'findOne', async () => null);
  }
});

test('GET gives the lock time only while locked', async () => {
  const until = new Date(Date.now() + 5 * 60 * 1000);
  const token = signedInAs(makeUser('customer', { passwordHash: HASH, passwordLockedUntil: until }));
  const res = await call('/api/users/me', { token });
  assert.equal(res.body.user.lockedUntil, until.toISOString());
  assert.equal('passwordLockedUntil' in res.body.user, false);

  mock.restoreAll();
  mock.method(Vendor, 'findOne', async () => null);
  const past = signedInAs(makeUser('customer', { passwordHash: HASH, passwordLockedUntil: new Date(Date.now() - 1000) }));
  assert.equal('lockedUntil' in (await call('/api/users/me', { token: past })).body.user, false);
});

test('cancelling an email change clears the pending email and its code', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);
  await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'new@example.com', currentPassword: PASSWORD },
  });

  const res = await call('/api/users/me/email', { method: 'DELETE', token });

  assert.equal(res.status, 200);
  assert.equal(user.pendingEmail, undefined);
  assert.equal(user.otpHash, undefined);
  const verify = await call('/api/users/me/email/verify', { method: 'POST', token, body: { code: emails[0].code } });
  assert.equal(verify.status, 400);
  assert.equal(user.email, 'customer@example.com');
});

test('GET says a Google-only account has no password', async () => {
  const token = signedInAs(makeUser('customer', { googleId: 'g-1' }));
  const res = await call('/api/users/me', { token });
  assert.equal(res.body.user.hasPassword, false);
});

test('GET includes the business profile for vendors', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  Vendor.findOne.mock.mockImplementation(async () => ({ stallName: 'Warung Test' }));

  const res = await call('/api/users/me', { token });

  assert.equal(res.body.user.vendor.stallName, 'Warung Test');
  assert.equal(res.body.user.hasVendorProfile, true);
});

// AC2: edit details

test('PATCH changes name and phone only', async () => {
  const user = makeUser();
  const token = signedInAs(user);

  const res = await call('/api/users/me', {
    method: 'PATCH', token,
    body: { name: '  New Name ', phone: ' 019-8765432 ', role: 'admin', email: 'x@y.co', emailVerified: false },
  });

  assert.equal(res.status, 200);
  assert.equal(user.name, 'New Name');
  assert.equal(user.phone, '019-8765432');
  assert.equal(user.role, 'customer');
  assert.equal(user.email, 'customer@example.com');
  assert.equal(user.emailVerified, true);
});

for (const [name, body] of [
  ['an empty body', {}],
  ['a blank name', { name: '  ' }],
  ['a long name', { name: 'A'.repeat(101) }],
  ['a bad phone', { phone: 'abc' }],
  ['a name that is not text', { name: 5 }],
]) {
  test(`PATCH rejects ${name} and saves nothing`, async () => {
    const token = signedInAs(makeUser());
    const res = await call('/api/users/me', { method: 'PATCH', token, body });
    assert.equal(res.status, 400);
    assert.ok(res.body.error);
    assert.equal(saved, 0);
  });
}

// AC4: change password

test('changing the password stores a new hash, emails a notice and returns a working token', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);

  const res = await call('/api/users/me/password', {
    method: 'POST', token, body: { currentPassword: PASSWORD, newPassword: 'newpass456' },
  });

  assert.equal(res.status, 200);
  assert.ok(await bcrypt.compare('newpass456', user.passwordHash));
  assert.ok(user.passwordChangedAt instanceof Date);
  assert.deepEqual(emails, [{ to: 'customer@example.com', purpose: 'password_changed' }]);
  assert.equal((await call('/api/users/me', { token: res.body.token })).status, 200);
  assert.equal('passwordHash' in res.body, false);
});

test('older tokens stop working after a password change', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  signedInAs(user);
  const iat = Math.floor(Date.now() / 1000) - 60;
  const oldToken = jwt.sign({ iat }, 'test-secret', { subject: user.id, expiresIn: '7d' });
  user.passwordChangedAt = new Date(Math.floor(Date.now() / 1000) * 1000);

  const res = await call('/api/users/me', { token: oldToken });

  assert.equal(res.status, 401);
});

test('a wrong current password changes nothing, without logging the user out', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);

  const res = await call('/api/users/me/password', {
    method: 'POST', token, body: { currentPassword: 'wrongpass1', newPassword: 'newpass456' },
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.code, 'WRONG_PASSWORD');
  assert.equal(user.passwordHash, HASH);
  assert.equal(user.passwordAttempts, 1);
  assert.equal(emails.length, 0);
});

test('wrong tries are shared across password and email changes, and lock both', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);
  const wrongPassword = { currentPassword: 'wrongpass1', newPassword: 'newpass456' };

  await call('/api/users/me/password', { method: 'POST', token, body: wrongPassword });
  await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'new@example.com', currentPassword: 'wrongpass1' },
  });
  const third = await call('/api/users/me/password', { method: 'POST', token, body: wrongPassword });

  assert.equal(third.status, 429);
  assert.ok(user.passwordLockedUntil > new Date());
  const right = await call('/api/users/me/password', {
    method: 'POST', token, body: { currentPassword: PASSWORD, newPassword: 'newpass456' },
  });
  assert.equal(right.status, 429);
  assert.equal(user.passwordHash, HASH);
});

test('the lock ends after 15 minutes and a right password clears the count', async () => {
  const user = makeUser('customer', {
    passwordHash: HASH, passwordAttempts: 2, passwordLockedUntil: new Date(Date.now() - 1000),
  });
  const token = signedInAs(user);

  const res = await call('/api/users/me/password', {
    method: 'POST', token, body: { currentPassword: PASSWORD, newPassword: 'newpass456' },
  });

  assert.equal(res.status, 200);
  assert.equal(user.passwordAttempts, 0);
  assert.equal(user.passwordLockedUntil, undefined);
});

for (const [name, newPassword] of [
  ['the same password', PASSWORD],
  ['a short password', 'ab1'],
  ['a password without a number', 'abcdefghij'],
  ['a password over 72 characters', `a1${'b'.repeat(71)}`],
]) {
  test(`changing to ${name} is rejected`, async () => {
    const user = makeUser('customer', { passwordHash: HASH });
    const token = signedInAs(user);

    const res = await call('/api/users/me/password', {
      method: 'POST', token, body: { currentPassword: PASSWORD, newPassword },
    });

    assert.equal(res.status, 400);
    assert.equal(user.passwordHash, HASH);
  });
}

test('a Google-only account cannot change a password', async () => {
  const user = makeUser('customer', { googleId: 'g-1' });
  const token = signedInAs(user);

  const res = await call('/api/users/me/password', {
    method: 'POST', token, body: { currentPassword: 'anything1', newPassword: 'newpass456' },
  });

  assert.equal(res.status, 400);
  assert.equal(user.passwordHash, undefined);
});

// AC3: change email

test('changing email sends a code to the new address and keeps the old email until it is entered', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);

  const res = await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: ' New@Example.com ', currentPassword: PASSWORD },
  });

  assert.equal(res.status, 200);
  assert.equal(res.body.pendingEmail, 'new@example.com');
  assert.equal(user.email, 'customer@example.com');
  assert.equal(user.pendingEmail, 'new@example.com');
  assert.equal(emails[0].to, 'new@example.com');
  assert.equal(emails[0].purpose, 'change_email');
});

test('the right code changes the email and notifies the old address', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);
  await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'new@example.com', currentPassword: PASSWORD },
  });

  const res = await call('/api/users/me/email/verify', { method: 'POST', token, body: { code: emails[0].code } });

  assert.equal(res.status, 200);
  assert.equal(user.email, 'new@example.com');
  assert.equal(user.pendingEmail, undefined);
  assert.equal(res.body.user.email, 'new@example.com');
  assert.deepEqual(emails[1], { to: 'customer@example.com', newEmail: 'new@example.com', purpose: 'email_changed' });
});

test('a wrong code keeps the old email and counts the attempt', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);
  await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'new@example.com', currentPassword: PASSWORD },
  });
  const wrong = emails[0].code === '000000' ? '111111' : '000000';

  const res = await call('/api/users/me/email/verify', { method: 'POST', token, body: { code: wrong } });

  assert.equal(res.status, 400);
  assert.equal(user.email, 'customer@example.com');
  assert.equal(user.otpAttempts, 1);
});

test('an email already in use is rejected without sending a code', async () => {
  const token = signedInAs(makeUser('customer', { passwordHash: HASH }));

  const res = await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'taken@example.com', currentPassword: PASSWORD },
  });

  assert.equal(res.status, 409);
  assert.equal(emails.length, 0);
});

test('changing email needs the right current password', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);

  const res = await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'new@example.com', currentPassword: 'wrongpass1' },
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.code, 'WRONG_PASSWORD');
  assert.equal(user.pendingEmail, undefined);
  assert.equal(emails.length, 0);
});

test('a Google-linked account cannot change its email', async () => {
  const token = signedInAs(makeUser('customer', { passwordHash: HASH, googleId: 'g-1' }));

  const res = await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'new@example.com', currentPassword: PASSWORD },
  });

  assert.equal(res.status, 400);
  assert.equal(res.body.code, 'GOOGLE_LINKED');
  assert.equal(emails.length, 0);
});

test('resending waits for the cooldown', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);
  await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'new@example.com', currentPassword: PASSWORD },
  });

  const res = await call('/api/users/me/email/resend', { method: 'POST', token });

  assert.equal(res.status, 200);
  assert.equal(emails.length, 1);
});

test('a second email change within a minute is refused without sending a code', async () => {
  const user = makeUser('customer', { passwordHash: HASH });
  const token = signedInAs(user);
  await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'new@example.com', currentPassword: PASSWORD },
  });

  const res = await call('/api/users/me/email', {
    method: 'POST', token, body: { newEmail: 'other@example.com', currentPassword: PASSWORD },
  });

  assert.equal(res.status, 429);
  assert.match(res.body.error, /less than a minute ago/);
  assert.equal(user.pendingEmail, 'new@example.com');
  assert.equal(emails.length, 1);
});

test('notice emails escape the name', () => {
  const { html } = emailService.buildPasswordChangedEmail('<b>Ann</b>');
  assert.match(html, /&lt;b&gt;Ann&lt;\/b&gt;/);
  const changed = emailService.buildEmailChangedEmail('Ann', 'new@example.com');
  assert.match(changed.text, /new@example\.com/);
});
