// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const Order = require('../src/models/Order');
const SalesRecord = require('../src/models/SalesRecord');
const { signToken } = require('../src/services/tokenService');
const { call } = require('./testServer');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });
const inHours = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000);

const vendorUser = makeUser('vendor');
const vendor = {
  _id: new mongoose.Types.ObjectId(),
  user: vendorUser._id,
  stallName: 'Warung Pak Din',
  address: 'Arked Meranti, UTM',
};

const makeListing = (overrides = {}) => new Listing({
  vendor: vendor._id,
  title: 'Nasi Lemak',
  category: 'Rice',
  isHalal: true,
  originalPrice: 8,
  discountedPrice: 4.5,
  quantityAvailable: 4,
  soldCount: 6,
  pickupStart: inHours(-1),
  pickupEnd: inHours(2),
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
  ...overrides,
});

beforeEach(() => mock.restoreAll());

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

function ownListing(listing, { activeOrders = 0, deleted = 1 } = {}) {
  const token = signedInAs(vendorUser);
  mock.method(Vendor, 'findOne', async () => vendor);
  mock.method(Listing, 'findOne', async () => listing);
  const count = mock.method(Order, 'countDocuments', async () => activeOrders);
  const create = mock.method(SalesRecord, 'create', async (doc) => ({ _id: new mongoose.Types.ObjectId(), ...doc }));
  const removeRecord = mock.method(SalesRecord, 'deleteOne', async () => ({ deletedCount: 1 }));
  const remove = mock.method(Listing, 'deleteOne', async () => ({ deletedCount: deleted }));
  return { token, count, create, removeRecord, remove };
}

const url = (listing) => `/api/listings/${listing?.id ?? new mongoose.Types.ObjectId()}`;

test('DELETE /:id returns 401 when not logged in', async () => {
  assert.equal((await call(url(), { method: 'DELETE' })).status, 401);
});

test('DELETE /:id returns 403 for other roles', async () => {
  for (const role of ['customer', 'admin']) {
    const token = signedInAs(makeUser(role));
    assert.equal((await call(url(), { method: 'DELETE', token })).status, 403, role);
    mock.restoreAll();
  }
});

test("deleting another vendor's listing returns 404", async () => {
  const { token, remove } = ownListing(null);
  const res = await call(url(), { method: 'DELETE', token });
  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'LISTING_NOT_FOUND');
  assert.equal(remove.mock.callCount(), 0);
});

test('active orders block deletion', async () => {
  const listing = makeListing();
  const { token, count, create, remove } = ownListing(listing, { activeOrders: 2 });
  const res = await call(url(listing), { method: 'DELETE', token });
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'ACTIVE_ORDERS');
  assert.equal(res.body.activeOrderCount, 2);
  assert.equal(new Date(res.body.pickupEnd).getTime(), listing.pickupEnd.getTime());
  assert.match(res.body.error, /2 active orders/);
  assert.equal(create.mock.callCount(), 0);
  assert.equal(remove.mock.callCount(), 0);
  const [filter] = count.mock.calls[0].arguments;
  assert.equal(String(filter.listing), String(listing._id));
  assert.ok(filter.pickupEnd.$gt instanceof Date);
});

test('deleting during pickup keeps the round so far as a sales record', async () => {
  const listing = makeListing();
  const { token, create, remove } = ownListing(listing);
  const before = Date.now();
  const res = await call(url(listing), { method: 'DELETE', token });
  assert.equal(res.status, 200);
  assert.equal(res.body.deleted, true);
  const [record] = create.mock.calls[0].arguments;
  assert.equal(record.reason, 'deleted');
  assert.equal(record.itemName, 'Nasi Lemak');
  assert.equal(record.stallName, 'Warung Pak Din');
  assert.equal(record.sold, 6);
  assert.equal(record.leftover, 4);
  assert.equal(record.stockOffered, 10);
  assert.ok(record.pickupEnd.getTime() >= before && record.pickupEnd < listing.pickupEnd);
  assert.equal(record.pickupStart.getTime(), listing.pickupStart.getTime());
  const [filter] = remove.mock.calls[0].arguments;
  assert.equal(String(filter._id), String(listing._id));
  assert.equal(String(filter.vendor), String(vendor._id));
});

test('deleting before pickup opens records the deletion time for both ends', async () => {
  const listing = makeListing({ pickupStart: inHours(1), soldCount: 2 });
  const { token, create } = ownListing(listing);
  await call(url(listing), { method: 'DELETE', token });
  const [record] = create.mock.calls[0].arguments;
  assert.equal(record.pickupStart.getTime(), record.pickupEnd.getTime());
});

test('deleting after pickup ended keeps the real pickup end', async () => {
  const listing = makeListing({ pickupStart: inHours(-4), pickupEnd: inHours(-2) });
  const { token, create } = ownListing(listing);
  await call(url(listing), { method: 'DELETE', token });
  const [record] = create.mock.calls[0].arguments;
  assert.equal(record.pickupEnd.getTime(), listing.pickupEnd.getTime());
});

test('a round that offered nothing saves no record', async () => {
  const listing = makeListing({ quantityAvailable: 0, soldCount: 0 });
  const { token, create, remove } = ownListing(listing);
  const res = await call(url(listing), { method: 'DELETE', token });
  assert.equal(res.status, 200);
  assert.equal(create.mock.callCount(), 0);
  assert.equal(remove.mock.callCount(), 1);
});

test('the record is removed again if the listing was already gone', async () => {
  const listing = makeListing();
  const { token, removeRecord } = ownListing(listing, { deleted: 0 });
  const res = await call(url(listing), { method: 'DELETE', token });
  assert.equal(res.status, 404);
  assert.equal(removeRecord.mock.callCount(), 1);
});

test('the record is removed again if deleting fails', async () => {
  const listing = makeListing();
  const { token, removeRecord } = ownListing(listing);
  mock.method(Listing, 'deleteOne', async () => {
    throw new Error('network');
  });
  const res = await call(url(listing), { method: 'DELETE', token });
  assert.equal(res.status, 500);
  assert.equal(removeRecord.mock.callCount(), 1);
});

test('relist records still default to the relist reason', () => {
  assert.equal(new SalesRecord({}).reason, 'relist');
});
