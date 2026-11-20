// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const Order = require('../src/models/Order');
const { signToken } = require('../src/services/tokenService');
const { listingEditError } = require('../src/validators/listingValidators');
const { call } = require('./testServer');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });
const inHours = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000);

const vendorUser = makeUser('vendor');
const vendor = { _id: new mongoose.Types.ObjectId(), user: vendorUser._id };

const makeListing = (overrides = {}) => new Listing({
  vendor: vendor._id,
  title: 'Nasi Lemak',
  description: 'With sambal',
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

const editOf = (listing, overrides = {}) => ({
  title: listing.title,
  description: listing.description,
  category: listing.category,
  isHalal: listing.isHalal,
  originalPrice: listing.originalPrice,
  discountedPrice: listing.discountedPrice,
  quantityAvailable: listing.quantityAvailable,
  expectedQuantity: listing.quantityAvailable,
  pickupStart: listing.pickupStart.toISOString(),
  pickupEnd: listing.pickupEnd.toISOString(),
  allergens: [],
  otherAllergens: [],
  ...overrides,
});

beforeEach(() => mock.restoreAll());

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

// Signs in the vendor with `listing` as their own, no same-named listing and no active orders.
function ownListing(listing, { sameName = null, activeOrders = 0 } = {}) {
  const token = signedInAs(vendorUser);
  mock.method(Vendor, 'findOne', async () => vendor);
  mock.method(Listing, 'findOne', async () => listing);
  const exists = mock.method(Listing, 'exists', async () => sameName);
  const count = mock.method(Order, 'countDocuments', async () => activeOrders);
  return { token, exists, count };
}

const url = (listing) => `/api/listings/${listing?.id ?? new mongoose.Types.ObjectId()}`;
const patch = (listing, token, body) => call(url(listing), { method: 'PATCH', token, body });

test('PATCH /:id returns 401 when not logged in', async () => {
  assert.equal((await call(url(), { method: 'PATCH', body: {} })).status, 401);
});

test('PATCH /:id returns 403 for other roles', async () => {
  for (const role of ['customer', 'admin']) {
    const token = signedInAs(makeUser(role));
    assert.equal((await call(url(), { method: 'PATCH', token, body: {} })).status, 403, role);
    mock.restoreAll();
  }
});

test("editing another vendor's listing returns 404", async () => {
  const { token } = ownListing(null);
  const res = await patch(null, token, editOf(makeListing()));
  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'LISTING_NOT_FOUND');
});

test('a vendor saves new details without touching stock they left alone', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => makeListing({ title: 'Nasi Lemak Ayam' }));
  const res = await patch(listing, token, editOf(listing, {
    title: '  Nasi Lemak Ayam ',
    discountedPrice: 4,
    isHalal: false,
    otherAllergens: ['durian'],
  }));
  assert.equal(res.status, 200);
  assert.equal(res.body.listing.title, 'Nasi Lemak Ayam');
  const [filter, change] = update.mock.calls[0].arguments;
  assert.equal(filter.quantityAvailable, undefined);
  assert.ok(filter.pickupEnd.$gt instanceof Date);
  assert.equal(change.$set.title, 'Nasi Lemak Ayam');
  assert.equal(change.$set.discountedPrice, 4);
  assert.equal(change.$set.isHalal, false);
  assert.equal(change.$set.quantityAvailable, undefined);
  assert.deepEqual(change.$set.otherAllergens, ['Durian']);
  for (const field of ['soldCount', 'status', 'location', 'vendor', 'listedAt']) {
    assert.equal(change.$set[field], undefined, field);
  }
});

test('a changed stock is saved only if it still matches what the vendor saw', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => makeListing({ quantityAvailable: 12 }));
  const res = await patch(listing, token, editOf(listing, { quantityAvailable: 12 }));
  assert.equal(res.status, 200);
  const [filter, change] = update.mock.calls[0].arguments;
  assert.equal(filter.quantityAvailable, 5);
  assert.equal(change.$set.quantityAvailable, 12);
});

test('an order during the edit returns STOCK_CHANGED with the current stock', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  mock.method(Listing, 'findOneAndUpdate', async () => null);
  mock.method(Listing, 'findById', async () => makeListing({ quantityAvailable: 3 }));
  const res = await patch(listing, token, editOf(listing, { quantityAvailable: 0 }));
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'STOCK_CHANGED');
  assert.equal(res.body.current, 3);
});

test('a cleared description is removed', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => makeListing({ description: undefined }));
  await patch(listing, token, editOf(listing, { description: '  ' }));
  const [, change] = update.mock.calls[0].arguments;
  assert.deepEqual(change.$unset, { description: '' });
  assert.equal(change.$set.description, undefined);
});

test('renaming to another of their listing names returns SAME_NAME', async () => {
  const listing = makeListing();
  const other = new mongoose.Types.ObjectId();
  const { token, exists } = ownListing(listing, { sameName: { _id: other } });
  const update = mock.method(Listing, 'findOneAndUpdate', async () => listing);
  const res = await patch(listing, token, editOf(listing, { title: 'mee  GORENG' }));
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'SAME_NAME');
  assert.equal(res.body.listingId, String(other));
  assert.equal(update.mock.callCount(), 0);
  const [query] = exists.mock.calls[0].arguments;
  assert.equal(String(query._id.$ne), String(listing._id));
  assert.ok(query.title.test('Mee Goreng'));
});

test('the pickup window is locked while the listing has active orders', async () => {
  const listing = makeListing();
  const { token, count } = ownListing(listing, { activeOrders: 2 });
  const update = mock.method(Listing, 'findOneAndUpdate', async () => listing);
  const res = await patch(listing, token, editOf(listing, { pickupEnd: inHours(3).toISOString() }));
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'PICKUP_LOCKED');
  assert.equal(update.mock.callCount(), 0);
  const [filter] = count.mock.calls[0].arguments;
  assert.equal(String(filter.listing), String(listing._id));
  assert.deepEqual(filter.status.$in, ['pending', 'confirmed']);
});

test('other fields still save while the listing has active orders', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing, { activeOrders: 2 });
  mock.method(Listing, 'findOneAndUpdate', async () => listing);
  const res = await patch(listing, token, editOf(listing, { discountedPrice: 4 }));
  assert.equal(res.status, 200);
});

test('a free listing can move its pickup window', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => listing);
  const end = inHours(5);
  const res = await patch(listing, token, editOf(listing, { pickupEnd: end.toISOString() }));
  assert.equal(res.status, 200);
  assert.equal(update.mock.calls[0].arguments[1].$set.pickupEnd.getTime(), end.getTime());
});

test('an ended or removed listing cannot be edited', async () => {
  for (const listing of [makeListing({ pickupEnd: inHours(-1) }), makeListing({ status: 'cancelled' })]) {
    const { token } = ownListing(listing);
    const res = await patch(listing, token, editOf(listing));
    assert.equal(res.status, 409);
    assert.equal(res.body.code, 'PICKUP_ENDED');
    mock.restoreAll();
  }
});

test('invalid edits are refused before anything is saved', async () => {
  const listing = makeListing();
  const { token } = ownListing(listing);
  const update = mock.method(Listing, 'findOneAndUpdate', async () => listing);
  const res = await patch(listing, token, editOf(listing, { discountedPrice: 9 }));
  assert.equal(res.status, 400);
  assert.equal(update.mock.callCount(), 0);
});

test('edit rules follow the create rules, with stock from 0', () => {
  const body = editOf(makeListing());
  assert.equal(listingEditError(body), null);
  assert.equal(listingEditError({ ...body, quantityAvailable: 0 }), null);
  assert.match(listingEditError({ ...body, quantityAvailable: 1000 }), /0 to 999/);
  assert.match(listingEditError({ ...body, expectedQuantity: undefined }), /Reload/);
  assert.match(listingEditError({ ...body, title: 'x' }), /2 to 80/);
  assert.equal(listingEditError({ ...body, pickupEnd: inHours(25).toISOString() }), 'Pickup must end within 24 hours.');
});

test('the vendor listing page gets the number of active orders', async () => {
  const listing = makeListing();
  const { token, count } = ownListing(listing, { activeOrders: 4 });
  const SalesRecord = require('../src/models/SalesRecord');
  mock.method(SalesRecord, 'aggregate', async () => []);
  const res = await call(`/api/listings/mine/${listing.id}`, { token });
  assert.equal(res.status, 200);
  assert.equal(res.body.activeOrderCount, 4);
  assert.equal(String(count.mock.calls[0].arguments[0].listing), String(listing._id));
});
