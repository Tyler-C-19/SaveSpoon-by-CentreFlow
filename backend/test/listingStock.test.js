// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const SalesRecord = require('../src/models/SalesRecord');
const { signToken } = require('../src/services/tokenService');
const { unavailableProblem, LISTING_GONE } = require('../src/services/orderService');
const { stockChangeError, availabilityError } = require('../src/validators/listingValidators');
const { call } = require('./testServer');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });
const inHours = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000);

const vendorUser = makeUser('vendor');
const vendor = { _id: new mongoose.Types.ObjectId(), user: vendorUser._id };

const makeListing = (overrides = {}) => new Listing({
  vendor: vendor._id,
  title: 'Nasi Lemak',
  category: 'Rice',
  isHalal: true,
  originalPrice: 8,
  discountedPrice: 4.5,
  quantityAvailable: 5,
  soldCount: 3,
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

// Signs in the vendor and makes `listing` their own listing (or none).
function ownListing(listing) {
  const token = signedInAs(vendorUser);
  mock.method(Vendor, 'findOne', async () => vendor);
  mock.method(SalesRecord, 'aggregate', async () => []);
  const findOne = mock.method(Listing, 'findOne', async () => listing);
  return { token, findOne };
}

const id = () => new mongoose.Types.ObjectId().toString();

for (const [method, url] of [
  ['GET', `/api/listings/mine/${id()}`],
  ['PATCH', `/api/listings/${id()}/stock`],
  ['PATCH', `/api/listings/${id()}/availability`],
]) {
  test(`${method} ${url.replace(/[0-9a-f]{24}/, ':id')} returns 401 when not logged in`, async () => {
    assert.equal((await call(url, { method, body: method === 'GET' ? undefined : {} })).status, 401);
  });

  test(`${method} ${url.replace(/[0-9a-f]{24}/, ':id')} returns 403 for other roles`, async () => {
    for (const role of ['customer', 'admin']) {
      const token = signedInAs(makeUser(role));
      assert.equal((await call(url, { method, token, body: method === 'GET' ? undefined : {} })).status, 403, role);
      mock.restoreAll();
    }
  });
}

test('a vendor reads one of their own listings', async () => {
  const listing = makeListing();
  const { token, findOne } = ownListing(listing);
  const res = await call(`/api/listings/mine/${listing.id}`, { token });
  assert.equal(res.status, 200);
  assert.equal(res.body.listing.title, 'Nasi Lemak');
  assert.equal(String(findOne.mock.calls[0].arguments[0].vendor), String(vendor._id));
});

test("another vendor's listing or a bad id returns 404", async () => {
  const { token } = ownListing(null);
  for (const url of [`/api/listings/mine/${id()}`, '/api/listings/mine/not-an-id']) {
    const res = await call(url, { token });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'LISTING_NOT_FOUND');
  }
  const stock = await call(`/api/listings/${id()}/stock`, {
    method: 'PATCH', token, body: { quantity: 3, expectedQuantity: 5 },
  });
  assert.equal(stock.status, 404);
  const off = await call(`/api/listings/${id()}/availability`, { method: 'PATCH', token, body: { paused: true } });
  assert.equal(off.status, 404);
});

test('a vendor without a profile gets NO_VENDOR_PROFILE', async () => {
  const token = signedInAs(vendorUser);
  mock.method(Vendor, 'findOne', async () => null);
  const res = await call(`/api/listings/mine/${id()}`, { token });
  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'NO_VENDOR_PROFILE');
});

test('stock is set only if it still matches what the vendor saw', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => makeListing({ quantityAvailable: 9 }));
  const res = await call(`/api/listings/${listing.id}/stock`, {
    method: 'PATCH', token, body: { quantity: 9, expectedQuantity: 5, soldCount: 0, status: 'active' },
  });
  assert.equal(res.status, 200);
  assert.equal(res.body.listing.quantityAvailable, 9);
  const [filter, change] = update.mock.calls[0].arguments;
  assert.equal(filter.quantityAvailable, 5);
  assert.deepEqual(filter.status, { $in: ['active', 'paused'] });
  assert.ok(filter.pickupEnd.$gt instanceof Date);
  assert.deepEqual(change, { $set: { quantityAvailable: 9 } });
});

test('an order placed while editing stops the save and reports the new stock', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  mock.method(Listing, 'findOneAndUpdate', async () => null);
  mock.method(Listing, 'findById', async () => makeListing({ quantityAvailable: 3 }));
  const res = await call(`/api/listings/${listing.id}/stock`, {
    method: 'PATCH', token, body: { quantity: 5, expectedQuantity: 5 },
  });
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'STOCK_CHANGED');
  assert.equal(res.body.current, 3);
  assert.equal(res.body.error, '2 items were ordered while you were editing. Current available stock is now 3.');
});

test('one order while editing reads naturally', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  mock.method(Listing, 'findOneAndUpdate', async () => null);
  mock.method(Listing, 'findById', async () => makeListing({ quantityAvailable: 4 }));
  const res = await call(`/api/listings/${listing.id}/stock`, {
    method: 'PATCH', token, body: { quantity: 8, expectedQuantity: 5 },
  });
  assert.equal(res.body.error, '1 item was ordered while you were editing. Current available stock is now 4.');
});

test('stock and the switch are refused once pickup has ended', async () => {
  const listing = makeListing({ pickupEnd: inHours(-1) });
  const { token } = ownListing(listing);
  mock.method(Listing, 'findOneAndUpdate', async () => null);
  mock.method(Listing, 'findById', async () => listing);
  const stock = await call(`/api/listings/${listing.id}/stock`, {
    method: 'PATCH', token, body: { quantity: 4, expectedQuantity: 5 },
  });
  assert.equal(stock.status, 409);
  assert.equal(stock.body.code, 'PICKUP_ENDED');
  const off = await call(`/api/listings/${listing.id}/availability`, { method: 'PATCH', token, body: { paused: true } });
  assert.equal(off.status, 409);
  assert.equal(off.body.error, 'Pickup has ended.');
});

test('restocking a sold-out listing keeps its sold count', async () => {
  const listing = makeListing({ quantityAvailable: 0, soldCount: 12 });
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => makeListing({ quantityAvailable: 4, soldCount: 12 }));
  const res = await call(`/api/listings/${listing.id}/stock`, {
    method: 'PATCH', token, body: { quantity: 4, expectedQuantity: 0 },
  });
  assert.equal(res.status, 200);
  assert.equal(res.body.listing.soldCount, 12);
  assert.equal('soldCount' in update.mock.calls[0].arguments[1].$set, false);
});

test('invalid stock changes save nothing', async () => {
  const { token } = ownListing(makeListing());
  const update = mock.method(Listing, 'findOneAndUpdate', async () => null);
  for (const body of [
    { quantity: -1, expectedQuantity: 5 },
    { quantity: 1000, expectedQuantity: 5 },
    { quantity: 2.5, expectedQuantity: 5 },
    { quantity: '4', expectedQuantity: 5 },
    { quantity: 4 },
  ]) {
    assert.equal((await call(`/api/listings/${id()}/stock`, { method: 'PATCH', token, body })).status, 400, JSON.stringify(body));
  }
  assert.equal(update.mock.callCount(), 0);
});

test('stock limits are 0 to 999 whole numbers', () => {
  assert.equal(stockChangeError({ quantity: 0, expectedQuantity: 0 }), null);
  assert.equal(stockChangeError({ quantity: 999, expectedQuantity: 1 }), null);
  assert.match(stockChangeError({ quantity: 1000, expectedQuantity: 1 }), /0 to 999/);
  assert.equal(availabilityError({ paused: false }), null);
  assert.ok(availabilityError({ paused: 'yes' }));
});

test('the switch turns a listing off and on and changes only its status', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async (_, change) => makeListing(change.$set));
  const off = await call(`/api/listings/${listing.id}/availability`, {
    method: 'PATCH', token, body: { paused: true, quantityAvailable: 999 },
  });
  assert.equal(off.status, 200);
  assert.equal(off.body.listing.status, 'paused');
  assert.deepEqual(update.mock.calls[0].arguments[1], { $set: { status: 'paused' } });

  const on = await call(`/api/listings/${listing.id}/availability`, { method: 'PATCH', token, body: { paused: false } });
  assert.equal(on.body.listing.status, 'active');
  assert.deepEqual(update.mock.calls[1].arguments[0].status, { $in: ['active', 'paused'] });
});

test('an invalid switch value saves nothing', async () => {
  const { token } = ownListing(makeListing());
  const update = mock.method(Listing, 'findOneAndUpdate', async () => null);
  const res = await call(`/api/listings/${id()}/availability`, { method: 'PATCH', token, body: { paused: 'off' } });
  assert.equal(res.status, 400);
  assert.equal(update.mock.callCount(), 0);
});

test('a turned-off listing reads as no longer available to customers', () => {
  assert.equal(unavailableProblem(makeListing({ status: 'paused' })).code, LISTING_GONE);
  assert.equal(unavailableProblem(makeListing()), null);
});
