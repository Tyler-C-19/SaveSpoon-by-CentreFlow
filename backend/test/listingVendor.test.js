// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const app = require('../src/app');
const User = require('../src/models/User');
const Listing = require('../src/models/Listing');
const Vendor = require('../src/models/Vendor');
const Cart = require('../src/models/Cart');
const { signToken } = require('../src/services/tokenService');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });
const hoursFromNow = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000);

const vendorDoc = (fields = {}) => new Vendor({
  user: new mongoose.Types.ObjectId(),
  stallName: 'Warung Pak Din',
  description: 'Home-style rice dishes',
  address: 'Cafeteria A, UTM Skudai',
  phone: '012-3456781',
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
  placeId: 'place-1',
  verified: true,
  ...fields,
});

const listingDoc = (vendor, fields = {}) => new Listing({
  vendor: vendor._id,
  title: 'Nasi Lemak',
  category: 'Rice',
  isHalal: true,
  originalPrice: 8,
  discountedPrice: 4.5,
  quantityAvailable: 5,
  pickupStart: hoursFromNow(1),
  pickupEnd: hoursFromNow(3),
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
  ...fields,
});

beforeEach(() => mock.restoreAll());

function setUp({ user = makeUser('customer'), listing, vendor, ownerPhoto, others = [] } = {}) {
  mock.method(User, 'findById', async (id) =>
    String(id) === String(user._id) ? user : { photoUrl: ownerPhoto }
  );
  mock.method(Listing, 'findById', async () => listing ?? null);
  mock.method(Vendor, 'findById', async () => vendor ?? null);
  const aggregate = mock.method(Listing, 'aggregate', async () => others);
  return { token: signToken(user.id), aggregate };
}

async function call(url, token) {
  const listener = app.listen(0);
  await new Promise((resolve) => listener.once('listening', resolve));
  try {
    const res = await globalThis.fetch(`http://127.0.0.1:${listener.address().port}${url}`, {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    });
    return { status: res.status, body: await res.json() };
  } finally {
    listener.closeAllConnections();
    await new Promise((resolve) => listener.close(resolve));
  }
}

const vendorUrl = (listing) => `/api/listings/${listing?._id ?? new mongoose.Types.ObjectId()}/vendor`;

test('vendor info returns 401 when not logged in', async () => {
  assert.equal((await call(vendorUrl())).status, 401);
});

test('vendor info returns 403 for vendors', async () => {
  const { token } = setUp({ user: makeUser('vendor') });
  assert.equal((await call(vendorUrl(), token)).status, 403);
});

test('vendor info shows the public stall details only', async () => {
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const { token } = setUp({ listing, vendor, ownerPhoto: 'https://cdn/face.jpg' });

  const res = await call(vendorUrl(listing), token);

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.vendor, {
    stallName: 'Warung Pak Din',
    description: 'Home-style rice dishes',
    address: 'Cafeteria A, UTM Skudai',
    phone: '012-3456781',
    photoUrl: 'https://cdn/face.jpg',
    location: [103.6385, 1.559],
    placeId: 'place-1',
  });
  const text = JSON.stringify(res.body);
  assert.equal(text.includes(String(vendor.user)), false);
  assert.equal(text.includes(String(vendor._id)), false);
  assert.equal(text.includes('verified'), false);
});

test('vendor info leaves out a missing picture, description and place', async () => {
  const vendor = vendorDoc({ description: undefined, placeId: undefined });
  const listing = listingDoc(vendor);
  const { token } = setUp({ listing, vendor });

  const res = await call(vendorUrl(listing), token);

  assert.equal(res.status, 200);
  for (const field of ['photoUrl', 'description', 'placeId']) {
    assert.equal(res.body.vendor[field], undefined, field);
  }
});

test('other listings are this stall\'s available ones, without the current one, up to 4', async () => {
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const other = { _id: 'other-1', title: 'Mee Goreng', stallName: 'Warung Pak Din' };
  const { token, aggregate } = setUp({ listing, vendor, others: [other] });

  const res = await call(vendorUrl(listing), token);

  assert.deepEqual(res.body.otherListings, [other]);
  const [pipeline] = aggregate.mock.calls[0].arguments;
  const [available, own] = pipeline;
  assert.equal(available.$match.status, 'active');
  assert.deepEqual(available.$match.quantityAvailable, { $gt: 0 });
  assert.ok(available.$match.pickupEnd.$gt instanceof Date);
  assert.equal(String(own.$match.vendor), String(vendor._id));
  assert.equal(String(own.$match._id.$ne), String(listing._id));
  assert.equal(pipeline.find((stage) => stage.$limit).$limit, 4);
  assert.deepEqual(Object.keys(pipeline.find((stage) => stage.$sort).$sort), ['soldCount', '_listedAt', '_id']);
  assert.equal(pipeline.find((stage) => stage.$sort).$sort.soldCount, -1);
  const projection = pipeline.at(-1).$project;
  assert.equal(projection.vendor, undefined);
  assert.equal(projection.location, '$location.coordinates');
});

test('from the map, the stall\'s items include the one used to open it', async () => {
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const { token, aggregate } = setUp({ listing, vendor });

  const res = await call(`${vendorUrl(listing)}?all=1`, token);

  assert.equal(res.status, 200);
  const [, own] = aggregate.mock.calls[0].arguments[0];
  assert.equal(String(own.$match.vendor), String(vendor._id));
  assert.equal(own.$match._id, undefined);
  assert.equal((await call(`${vendorUrl(listing)}?all=yes`, token)).status, 400);
});

test('vendor info returns 404 when the listing or vendor is gone', async () => {
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);

  let { token } = setUp({ listing });
  assert.equal((await call(vendorUrl(listing), token)).status, 404);
  mock.restoreAll();

  ({ token } = setUp({ vendor }));
  assert.equal((await call(vendorUrl(listing), token)).status, 404);
  mock.restoreAll();

  ({ token } = setUp({ listing: listingDoc(vendor, { status: 'cancelled' }), vendor }));
  assert.equal((await call(vendorUrl(listing), token)).status, 404);
  mock.restoreAll();

  ({ token } = setUp({}));
  const res = await call('/api/listings/not-an-id/vendor', token);
  assert.equal(res.status, 404);
  assert.equal(res.body.error, 'This item is no longer available.');
});

test('food details include the pickup pin, place and contact number', async () => {
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const { token } = setUp({ listing, vendor });

  const res = await call(`/api/listings/${listing._id}`, token);

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.listing.pickupLocation, [103.6385, 1.559]);
  assert.equal(res.body.listing.pickupPlaceId, 'place-1');
  assert.equal(res.body.listing.vendorPhone, '012-3456781');
  assert.equal(res.body.listing.vendor, undefined);
  assert.equal(JSON.stringify(res.body).includes(String(vendor.user)), false);
});

test('cart items carry their stall\'s pickup pin', async () => {
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const user = makeUser('customer');
  const cart = new Cart({
    customer: user._id,
    items: [{ listing: listing._id, quantity: 1, itemName: 'Nasi Lemak', stallName: 'Warung Pak Din', unitPriceWhenAdded: 4.5 }],
  });
  mock.method(User, 'findById', async () => user);
  mock.method(Cart, 'findOne', async () => cart);
  mock.method(Listing, 'find', async () => [listing]);
  mock.method(Vendor, 'find', async () => [vendor]);

  const res = await call('/api/cart', signToken(user.id));

  assert.equal(res.status, 200);
  const [item] = res.body.cart.items;
  assert.deepEqual(item.pickupLocation, [103.6385, 1.559]);
  assert.equal(item.pickupPlaceId, 'place-1');
});
