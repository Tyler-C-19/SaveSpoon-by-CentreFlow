// These tests replace database calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Notification = require('../src/models/Notification');
const notifications = require('../src/services/notificationService');
const { signToken } = require('../src/services/tokenService');

const makeUser = (role, prefs) => new User({
  name: 'Test', email: `${role}@example.com`, role, emailVerified: true, notificationPrefs: prefs,
});

function signedInAs(user) {
  mock.method(User, 'findById', () => query(user));
  return signToken(user.id);
}

let updates;

beforeEach(() => {
  mock.restoreAll();
  updates = [];
  mock.method(User, 'updateMany', async (filter, change) => updates.push(['many', filter, change]));
  mock.method(User, 'updateOne', async (filter, change) => updates.push(['one', filter, change]));
  mock.method(notifications, 'addDueReminders', async () => {});
});

for (const [method, url] of [
  ['GET', '/api/notifications'],
  ['GET', '/api/notifications/unread-count'],
  ['PUT', '/api/notifications/devices'],
  ['GET', '/api/notifications/preferences'],
]) {
  test(`${method} ${url} needs a customer or vendor`, async () => {
    assert.equal((await call(url, { method })).status, 401);
    const token = signedInAs(makeUser('admin'));
    assert.equal((await call(url, { method, token })).status, 403);
  });
}

test('registering a device moves the token off other accounts and keeps the newest 5', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);

  const res = await call('/api/notifications/devices', { method: 'PUT', token, body: { token: 'phone-1' } });

  assert.equal(res.status, 200);
  assert.deepEqual(updates[0], ['many', { _id: { $ne: user._id }, deviceTokens: 'phone-1' }, { $pull: { deviceTokens: 'phone-1' } }]);
  assert.deepEqual(updates[1], ['one', { _id: user._id }, { $pull: { deviceTokens: 'phone-1' } }]);
  assert.deepEqual(updates[2], ['one', { _id: user._id }, { $push: { deviceTokens: { $each: ['phone-1'], $slice: -5 } } }]);
});

test('a missing or empty device token is refused', async () => {
  const token = signedInAs(makeUser('vendor'));
  for (const body of [{}, { token: '' }, { token: 42 }, { token: 'x'.repeat(4097) }]) {
    const res = await call('/api/notifications/devices', { method: 'PUT', token, body });
    assert.equal(res.status, 400);
  }
  assert.equal(updates.length, 0);
});

test('logging out removes only that phone', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);

  const res = await call('/api/notifications/devices', { method: 'DELETE', token, body: { token: 'phone-1' } });

  assert.equal(res.status, 200);
  assert.deepEqual(updates, [['one', { _id: user._id }, { $pull: { deviceTokens: 'phone-1' } }]]);
});

test('preferences show only the switches for the role, on by default', async () => {
  let res = await call('/api/notifications/preferences', { token: signedInAs(makeUser('vendor')) });
  assert.deepEqual(res.body, { prefs: { orderAlerts: true, stockAlerts: true } });

  res = await call('/api/notifications/preferences', {
    token: signedInAs(makeUser('customer', { pickupReminders: false })),
  });
  assert.deepEqual(res.body, { prefs: { itemChanges: true, pickupReminders: false, favourites: true } });
});

test('saving preferences sets only the switches sent', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  let saved;
  mock.method(User, 'findOneAndUpdate', async (filter, change) => {
    saved = change;
    return makeUser('customer', { favourites: false });
  });

  const res = await call('/api/notifications/preferences', { method: 'PUT', token, body: { prefs: { favourites: false } } });

  assert.equal(res.status, 200);
  assert.deepEqual(saved, { $set: { 'notificationPrefs.favourites': false } });
  assert.equal(res.body.prefs.favourites, false);
});

test('a switch from the other role or a non-boolean is refused', async () => {
  const token = signedInAs(makeUser('vendor'));
  mock.method(User, 'findOneAndUpdate', async () => assert.fail('nothing should be saved'));
  for (const prefs of [{ favourites: false }, { orderAlerts: 'no' }, {}, null, []]) {
    const res = await call('/api/notifications/preferences', { method: 'PUT', token, body: { prefs } });
    assert.equal(res.status, 400);
  }
});

function mockInbox(items, unread) {
  const finds = [];
  mock.method(Notification, 'find', async (filter, fields, options) => {
    finds.push({ filter, options });
    return items;
  });
  mock.method(Notification, 'countDocuments', async () => unread);
  return finds;
}

test('the inbox lists the newest 50 from the last 30 days with the unread count', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  const finds = mockInbox([{ _id: 'n1', title: 'Pickup Soon' }], 1);

  const res = await call('/api/notifications', { token });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { notifications: [{ _id: 'n1', title: 'Pickup Soon' }], unreadCount: 1 });
  assert.equal(finds[0].options.limit, 50);
  assert.deepEqual(finds[0].options.sort, { createdAt: -1, _id: -1 });
  const since = Date.now() - finds[0].filter.createdAt.$gt.getTime();
  assert.ok(Math.abs(since - 30 * 24 * 60 * 60 * 1000) < 60 * 1000);
  assert.equal(notifications.addDueReminders.mock.callCount(), 1);
});

test('vendors get no pickup reminders added', async () => {
  const token = signedInAs(makeUser('vendor'));
  mockInbox([], 0);

  await call('/api/notifications/unread-count', { token });

  assert.equal(notifications.addDueReminders.mock.callCount(), 0);
});

test('a failed reminder check still returns the inbox', async () => {
  const token = signedInAs(makeUser('customer'));
  mockInbox([], 0);
  notifications.addDueReminders.mock.mockImplementation(async () => { throw new Error('down'); });
  mock.method(console, 'error', () => {});

  const res = await call('/api/notifications/unread-count', { token });

  assert.deepEqual(res.body, { unreadCount: 0 });
});

test('marking read only touches the user\'s own notification', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  const id = String(new mongoose.Types.ObjectId());
  let filter;
  mock.method(Notification, 'findOneAndUpdate', async (given) => {
    filter = given;
    return null;
  });

  assert.equal((await call(`/api/notifications/${id}/read`, { method: 'POST', token })).status, 404);
  assert.deepEqual(filter, { _id: id, user: user._id });
  assert.equal((await call('/api/notifications/nope/read', { method: 'POST', token })).status, 404);
});

test('Mark All as Read marks only the user\'s unread notifications', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  let given;
  mock.method(Notification, 'updateMany', async (filter, change) => {
    given = [filter, change];
  });

  const res = await call('/api/notifications/read-all', { method: 'POST', token, body: {} });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { unreadCount: 0 });
  assert.deepEqual(given[0], { user: user._id, readAt: null });
  assert.ok(given[1].$set.readAt instanceof Date);
});

test('clearing one hides it, keeps it until it expires and returns the unread count', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  const id = String(new mongoose.Types.ObjectId());
  let given;
  mock.method(Notification, 'updateOne', async (filter, change) => {
    given = [filter, change];
    return { matchedCount: 1 };
  });
  mock.method(Notification, 'countDocuments', async (filter) => {
    assert.equal(filter.clearedAt, null);
    return 2;
  });

  const res = await call(`/api/notifications/${id}`, { method: 'DELETE', token });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { unreadCount: 2 });
  assert.deepEqual(given[0], { _id: id, user: user._id, clearedAt: null });
  assert.ok(given[1].$set.clearedAt instanceof Date);
  assert.ok(given[1].$min.readAt instanceof Date);
});

test('clearing another user\'s or a missing notification is not found', async () => {
  const token = signedInAs(makeUser('customer'));
  mock.method(Notification, 'updateOne', async () => ({ matchedCount: 0 }));
  const id = String(new mongoose.Types.ObjectId());
  assert.equal((await call(`/api/notifications/${id}`, { method: 'DELETE', token })).status, 404);
  assert.equal((await call('/api/notifications/nope', { method: 'DELETE', token })).status, 404);
});

test('Clear All hides every notification of the user', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  let given;
  mock.method(Notification, 'updateMany', async (filter, change) => {
    given = [filter, change];
  });

  const res = await call('/api/notifications', { method: 'DELETE', token });

  assert.deepEqual(res.body, { unreadCount: 0 });
  assert.deepEqual(given[0], { user: user._id, clearedAt: null });
});

test('the inbox leaves cleared notifications out', async () => {
  const token = signedInAs(makeUser('vendor'));
  const finds = mockInbox([], 0);
  await call('/api/notifications', { token });
  assert.equal(finds[0].filter.clearedAt, null);
});

test('device tokens never appear in the user JSON', () => {
  const user = new User({ name: 'A', email: 'a@example.com', deviceTokens: ['secret'] });
  assert.equal(user.toJSON().deviceTokens, undefined);
});
