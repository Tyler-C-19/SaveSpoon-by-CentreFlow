// These tests replace database calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const Order = require('../src/models/Order');
const { signToken } = require('../src/services/tokenService');

const OLD = {
  _id: 'vendor-1',
  stallName: 'Warung Test',
  phone: '012-3456789',
  address: 'Cafeteria A, UTM Skudai',
  description: 'Rice',
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
  placeId: 'place-1',
};

const body = {
  stallName: 'Warung Baru',
  phone: '012-3456789',
  address: 'Cafeteria A, UTM Skudai',
  description: 'Rice and noodles',
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
};

let update;
let listingUpdate;
let activeOrders;

function signedInAs(role = 'vendor') {
  const user = new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });
  mock.method(User, 'findById', () => query(user));
  return signToken(user.id);
}

beforeEach(() => {
  mock.restoreAll();
  activeOrders = 0;
  mock.method(Vendor, 'findOne', async () => OLD);
  update = mock.method(Vendor, 'findOneAndUpdate', async (filter, change) => ({ ...OLD, ...change.$set }));
  listingUpdate = mock.method(Listing, 'updateMany', async () => ({ modifiedCount: 4 }));
  mock.method(Order, 'countDocuments', async () => activeOrders);
});

const put = (change, token = signedInAs()) =>
  call('/api/vendors/me', { method: 'PUT', token, body: { ...body, ...change } });

test('PUT returns 401 when logged out and 403 for other roles', async () => {
  assert.equal((await call('/api/vendors/me', { method: 'PUT', body })).status, 401);
  for (const role of ['customer', 'admin']) {
    assert.equal((await put({}, signedInAs(role))).status, 403, role);
    mock.restoreAll();
  }
});

test('editing details without moving the pin leaves listings and the place ID alone', async () => {
  const res = await put({});

  assert.equal(res.status, 200);
  const [filter, change] = update.mock.calls[0].arguments;
  assert.deepEqual(filter, { _id: 'vendor-1' });
  assert.equal(change.$set.stallName, 'Warung Baru');
  assert.equal('location' in change.$set, false);
  assert.equal(change.$unset, undefined);
  assert.equal(listingUpdate.mock.callCount(), 0);
  assert.equal(res.body.listingsUpdated, 0);
});

test('a hand-moved pin updates every listing and clears the place ID', async () => {
  const location = { type: 'Point', coordinates: [103.64, 1.56] };

  const res = await put({ location });

  assert.equal(res.status, 200);
  const change = update.mock.calls[0].arguments[1];
  assert.deepEqual(change.$set.location, location);
  assert.deepEqual(change.$unset, { placeId: 1 });
  assert.deepEqual(listingUpdate.mock.calls[0].arguments, [{ vendor: 'vendor-1' }, { location }]);
  assert.equal(res.body.listingsUpdated, 4);
});

test('a pin from a suggestion keeps its place ID', async () => {
  await put({ location: { type: 'Point', coordinates: [103.64, 1.56] }, placeId: 'place-2' });

  const change = update.mock.calls[0].arguments[1];
  assert.equal(change.$set.placeId, 'place-2');
  assert.equal(change.$unset, undefined);
});

test('a client cannot set user or verified', async () => {
  await put({ user: 'someone-else', verified: true });

  const change = update.mock.calls[0].arguments[1];
  assert.equal('user' in change.$set, false);
  assert.equal('verified' in change.$set, false);
});

test('a pin change is blocked while there are active orders', async () => {
  activeOrders = 2;

  const res = await put({ location: { type: 'Point', coordinates: [103.64, 1.56] } });

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'ACTIVE_ORDERS');
  assert.equal(update.mock.callCount(), 0);
  assert.equal(listingUpdate.mock.callCount(), 0);
});

test('an address change is blocked while there are active orders', async () => {
  activeOrders = 1;
  const res = await put({ address: 'Arked Meranti' });
  assert.equal(res.status, 409);
  assert.equal(update.mock.callCount(), 0);
});

test('other edits are allowed while there are active orders', async () => {
  activeOrders = 3;
  const res = await put({ stallName: 'New Name' });
  assert.equal(res.status, 200);
});

test('PUT rejects invalid input and saves nothing', async () => {
  for (const change of [{ stallName: 'A' }, { phone: 'abc' }, { address: ' ' }, { location: undefined }]) {
    const res = await put(change);
    assert.equal(res.status, 400);
  }
  assert.equal(update.mock.callCount(), 0);
});

test('PUT returns 404 before setup', async () => {
  Vendor.findOne.mock.mockImplementation(async () => null);
  const res = await put({});
  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'NO_VENDOR_PROFILE');
});
