// These tests replace database and Cloudinary calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const Order = require('../src/models/Order');
const Cart = require('../src/models/Cart');
const photoService = require('../src/services/photoService');
const accountService = require('../src/services/accountService');
const { signToken } = require('../src/services/tokenService');

const PASSWORD = 'secret123';
const HASH = bcrypt.hashSync(PASSWORD, 4);
const VENDOR = { _id: 'vendor-1', stallName: 'Warung Test' };

let deleted;
let counts;

function signedInAs(user) {
  mock.method(User, 'findById', () => query(user));
  return signToken(user.id);
}

const makeUser = (role, extra = {}) =>
  new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true, passwordHash: HASH, ...extra });

beforeEach(() => {
  mock.restoreAll();
  deleted = [];
  counts = { listings: 3, activeListings: 0, activeOrders: 0 };
  mock.method(Vendor, 'findOne', async () => VENDOR);
  mock.method(Listing, 'countDocuments', async (filter) => (filter.status ? counts.activeListings : counts.listings));
  mock.method(Order, 'countDocuments', async () => counts.activeOrders);
  mock.method(Listing, 'deleteMany', async (filter) => deleted.push(['listings', filter]));
  mock.method(Vendor, 'deleteOne', async (filter) => deleted.push(['vendor', filter]));
  mock.method(Cart, 'deleteOne', async (filter) => deleted.push(['cart', filter]));
  mock.method(User, 'deleteOne', async (filter) => deleted.push(['user', filter]));
  mock.method(photoService, 'remove', async (id) => deleted.push(['photo', id]));
  mock.method(User.prototype, 'save', async function save() { return this; });
  mock.method(console, 'error', () => {});
});

test('a vendor deletion removes listings, profile, photo and user, and leaves orders', async () => {
  const user = makeUser('vendor', { photoId: 'photo-1' });
  const token = signedInAs(user);
  const orderDelete = mock.method(Order, 'deleteMany', async () => ({}));

  const res = await call('/api/users/me', { method: 'DELETE', token, body: { password: PASSWORD } });

  assert.equal(res.status, 200);
  assert.deepEqual(deleted, [
    ['listings', { vendor: 'vendor-1' }],
    ['vendor', { _id: 'vendor-1' }],
    ['cart', { customer: user._id }],
    ['user', { _id: user._id }],
    ['photo', 'photo-1'],
  ]);
  assert.equal(orderDelete.mock.callCount(), 0);
});

test('a customer deletion removes the cart and user only', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  const vendorLookup = Vendor.findOne;
  vendorLookup.mock.mockImplementation(async () => null);

  const res = await call('/api/users/me', { method: 'DELETE', token, body: { password: PASSWORD } });

  assert.equal(res.status, 200);
  assert.deepEqual(deleted.map(([what]) => what), ['cart', 'user']);
  assert.equal(vendorLookup.mock.callCount(), 0);
});

test('a wrong password deletes nothing', async () => {
  const token = signedInAs(makeUser('customer'));

  const res = await call('/api/users/me', { method: 'DELETE', token, body: { password: 'wrongpass1' } });

  assert.equal(res.status, 400);
  assert.equal(res.body.code, 'WRONG_PASSWORD');
  assert.match(res.body.error, /2 tries left/);
  assert.deepEqual(deleted, []);
});

test('three wrong passwords lock deletion for 15 minutes, even with the right one', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);

  for (const left of ['2 tries left', '1 try left']) {
    const res = await call('/api/users/me', { method: 'DELETE', token, body: { password: 'wrongpass1' } });
    assert.match(res.body.error, new RegExp(left));
  }
  const third = await call('/api/users/me', { method: 'DELETE', token, body: { password: 'wrongpass1' } });
  assert.equal(third.status, 429);
  assert.equal(third.body.code, 'TOO_MANY_TRIES');
  assert.match(third.body.error, /15 minutes/);

  const right = await call('/api/users/me', { method: 'DELETE', token, body: { password: PASSWORD } });
  assert.equal(right.status, 429);
  assert.deepEqual(deleted, []);
});

test('a Google-only account confirms by typing DELETE', async () => {
  const token = signedInAs(makeUser('customer', { passwordHash: undefined, googleId: 'g-1' }));

  assert.equal((await call('/api/users/me', { method: 'DELETE', token, body: { confirm: 'delete' } })).status, 400);
  assert.deepEqual(deleted, []);

  const res = await call('/api/users/me', { method: 'DELETE', token, body: { confirm: 'DELETE' } });
  assert.equal(res.status, 200);
});

test('a vendor with active listings cannot delete', async () => {
  const token = signedInAs(makeUser('vendor'));
  counts.activeListings = 2;

  const res = await call('/api/users/me', { method: 'DELETE', token, body: { password: PASSWORD } });

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'ACCOUNT_DELETE_BLOCKED');
  assert.match(res.body.error, /2 active listings/);
  assert.deepEqual(deleted, []);
});

test('a vendor with active orders cannot delete', async () => {
  const token = signedInAs(makeUser('vendor'));
  counts.activeOrders = 1;

  const res = await call('/api/users/me', { method: 'DELETE', token, body: { password: PASSWORD } });

  assert.equal(res.status, 409);
  assert.match(res.body.error, /1 active order\b/);
  assert.deepEqual(deleted, []);
});

test('a customer with active orders cannot delete', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  counts.activeOrders = 2;
  const orderCount = Order.countDocuments;

  const res = await call('/api/users/me', { method: 'DELETE', token, body: { password: PASSWORD } });

  assert.equal(res.status, 409);
  assert.equal(orderCount.mock.calls[0].arguments[0].customer, user._id);
  assert.deepEqual(deleted, []);
});

test('the summary gives the counts for the warning popups', async () => {
  const token = signedInAs(makeUser('vendor'));
  counts.activeListings = 1;

  const res = await call('/api/users/me/summary', { token });

  assert.deepEqual(res.body, { listingCount: 3, activeListingCount: 1, activeOrderCount: 0 });
});

test('active orders are pending or confirmed with pickup still open', () => {
  const now = new Date('2026-11-08T10:00:00Z');
  assert.deepEqual(accountService.activeOrderFilter({ vendor: 'v1' }, now), {
    vendor: 'v1', status: { $in: ['pending', 'confirmed'] }, pickupEnd: { $gt: now },
  });
});

test('active listings are listed, in stock and still open for pickup', () => {
  const now = new Date('2026-11-08T10:00:00Z');
  assert.deepEqual(accountService.activeListingFilter('v1', now), {
    vendor: 'v1', status: 'active', quantityAvailable: { $gt: 0 }, pickupEnd: { $gt: now },
  });
});

test('a deleted account can no longer use its token', async () => {
  const token = signToken('5f0000000000000000000001');
  mock.method(User, 'findById', () => query(null));
  assert.equal((await call('/api/users/me', { token })).status, 401);
});
