// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const SalesRecord = require('../src/models/SalesRecord');
const Order = require('../src/models/Order');
const { signToken } = require('../src/services/tokenService');
const { relistError } = require('../src/validators/listingValidators');
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
  quantityAvailable: 2,
  soldCount: 10,
  pickupStart: inHours(-4),
  pickupEnd: inHours(-2),
  status: 'paused',
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
  ...overrides,
});

const newRound = () => ({
  quantityAvailable: 15,
  pickupStart: inHours(1).toISOString(),
  pickupEnd: inHours(3).toISOString(),
});

beforeEach(() => mock.restoreAll());

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

function ownListing(listing, { pastSold = 0 } = {}) {
  const token = signedInAs(vendorUser);
  mock.method(Vendor, 'findOne', async () => vendor);
  mock.method(Listing, 'findOne', async () => listing);
  const aggregate = mock.method(SalesRecord, 'aggregate', async () => (pastSold ? [{ sold: pastSold }] : []));
  mock.method(Order, 'countDocuments', async () => 0);
  return { token, aggregate };
}

const url = (listing) => `/api/listings/${listing?.id ?? new mongoose.Types.ObjectId()}/relist`;

test('POST /:id/relist returns 401 when not logged in', async () => {
  assert.equal((await call(url(), { method: 'POST', body: newRound() })).status, 401);
});

test('POST /:id/relist returns 403 for other roles', async () => {
  for (const role of ['customer', 'admin']) {
    const token = signedInAs(makeUser(role));
    assert.equal((await call(url(), { method: 'POST', token, body: newRound() })).status, 403, role);
    mock.restoreAll();
  }
});

test("relisting another vendor's listing returns 404", async () => {
  const { token } = ownListing(null);
  const res = await call(url(), { method: 'POST', token, body: newRound() });
  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'LISTING_NOT_FOUND');
});

test('relist saves the finished round, then resets the same listing', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing, { pastSold: 4 });
  const update = mock.method(Listing, 'findOneAndUpdate', async () => listing);
  const create = mock.method(SalesRecord, 'create', async (doc) => doc);
  const after = makeListing({ quantityAvailable: 15, soldCount: 0, status: 'active', pickupEnd: inHours(3) });
  mock.method(Listing, 'findById', async () => after);

  const res = await call(url(listing), { method: 'POST', token, body: { ...newRound(), soldCount: 99, title: 'X' } });

  assert.equal(res.status, 200);
  assert.equal(res.body.listing.quantityAvailable, 15);
  assert.equal(res.body.listing.soldCount, 0);
  assert.equal(res.body.pastSold, 4);

  const [filter, change, options] = update.mock.calls[0].arguments;
  assert.equal(String(filter._id), String(listing._id));
  assert.equal(filter.pickupEnd.getTime(), listing.pickupEnd.getTime());
  assert.equal(change.$set.quantityAvailable, 15);
  assert.equal(change.$set.soldCount, 0);
  assert.equal(change.$set.status, 'active');
  assert.ok(change.$set.listedAt instanceof Date);
  assert.equal('title' in change.$set, false);
  assert.equal(options.returnDocument, 'before');

  const record = create.mock.calls[0].arguments[0];
  assert.equal(String(record.listing), String(listing._id));
  assert.equal(String(record.vendor), String(vendor._id));
  assert.equal(record.stallName, 'Warung Pak Din');
  assert.equal(record.pickupAddress, 'Arked Meranti, UTM');
  assert.equal(record.itemName, 'Nasi Lemak');
  assert.equal(record.discountedPrice, 4.5);
  assert.equal(record.sold, 10);
  assert.equal(record.leftover, 2);
  assert.equal(record.stockOffered, 12);
  assert.equal(record.pickupEnd.getTime(), listing.pickupEnd.getTime());
});

test('relist can bring the listing back turned off', async () => {
  const listing = makeListing({ status: 'active' });
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => listing);
  mock.method(SalesRecord, 'create', async (doc) => doc);
  mock.method(Listing, 'findById', async () => makeListing({ status: 'paused', pickupEnd: inHours(3) }));

  const res = await call(url(listing), { method: 'POST', token, body: { ...newRound(), paused: true } });

  assert.equal(res.status, 200);
  assert.equal(update.mock.calls[0].arguments[1].$set.status, 'paused');
  assert.equal(res.body.listing.status, 'paused');
});

test('relist is refused while pickup is still open', async () => {
  const listing = makeListing({ pickupEnd: inHours(1) });
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => null);
  const res = await call(url(listing), { method: 'POST', token, body: newRound() });
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'PICKUP_NOT_ENDED');
  assert.equal(update.mock.callCount(), 0);
});

test('a second relist of the same round saves no second record', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  mock.method(Listing, 'findOneAndUpdate', async () => null);
  const create = mock.method(SalesRecord, 'create', async (doc) => doc);
  const res = await call(url(listing), { method: 'POST', token, body: newRound() });
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'ALREADY_RELISTED');
  assert.equal(create.mock.callCount(), 0);
});

test('if the record cannot be saved, the listing reset is undone', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  mock.method(Listing, 'findOneAndUpdate', async () => listing);
  mock.method(SalesRecord, 'create', async () => {
    throw new Error('write failed');
  });
  const undo = mock.method(Listing, 'updateOne', async () => ({ modifiedCount: 1 }));
  mock.method(console, 'error', () => {});

  const res = await call(url(listing), { method: 'POST', token, body: newRound() });

  assert.equal(res.status, 500);
  const [, change] = undo.mock.calls[0].arguments;
  assert.equal(change.$set.quantityAvailable, 2);
  assert.equal(change.$set.soldCount, 10);
  assert.equal(change.$set.status, 'paused');
  assert.equal(change.$set.pickupEnd.getTime(), listing.pickupEnd.getTime());
});

test('invalid relist input saves nothing', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => listing);
  for (const body of [
    { ...newRound(), quantityAvailable: 0 },
    { ...newRound(), quantityAvailable: 1000 },
    { ...newRound(), pickupEnd: inHours(-1).toISOString() },
    { ...newRound(), pickupEnd: inHours(30).toISOString() },
    { ...newRound(), paused: 'yes' },
    { quantityAvailable: 5 },
  ]) {
    assert.equal((await call(url(listing), { method: 'POST', token, body })).status, 400, JSON.stringify(body));
  }
  assert.equal(update.mock.callCount(), 0);
});

test('relist rules follow the create rules for stock and pickup', () => {
  assert.equal(relistError(newRound()), null);
  assert.match(relistError({ ...newRound(), quantityAvailable: 0 }), /1 to 999/);
  assert.equal(relistError({ ...newRound(), pickupEnd: newRound().pickupStart }), 'Pickup must end after it starts.');
});

test('the vendor listing page gets the items sold in earlier rounds', async () => {
  const listing = makeListing();
  const { token, aggregate } = ownListing(listing, { pastSold: 37 });
  const res = await call(`/api/listings/mine/${listing.id}`, { token });
  assert.equal(res.body.pastSold, 37);
  const [match] = aggregate.mock.calls[0].arguments[0];
  assert.equal(String(match.$match.listing), String(listing._id));
});

test('new listings are stamped with when they went on sale', () => {
  const listing = new Listing({});
  assert.ok(listing.listedAt instanceof Date);
});
