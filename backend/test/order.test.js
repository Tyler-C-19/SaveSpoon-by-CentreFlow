// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const app = require('../src/app');
const User = require('../src/models/User');
const Listing = require('../src/models/Listing');
const Vendor = require('../src/models/Vendor');
const Order = require('../src/models/Order');
const { signToken } = require('../src/services/tokenService');
const { sampleListings } = require('../seed/sampleListings');
const { sampleOrders, sampleCart, SAMPLE_ORDERS } = require('../seed/sampleOrders');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });

const hoursFromNow = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000);

const vendorDoc = () => new Vendor({
  user: new mongoose.Types.ObjectId(),
  stallName: 'Warung Pak Din',
  address: 'Cafeteria A, UTM Skudai',
  phone: '012-3456781',
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
});

const listingDoc = (vendor, fields = {}) => new Listing({
  vendor: vendor._id,
  title: 'Nasi Lemak',
  category: 'Rice',
  isHalal: true,
  originalPrice: 8,
  discountedPrice: 4.55,
  quantityAvailable: 5,
  pickupStart: hoursFromNow(1),
  pickupEnd: hoursFromNow(3),
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
  ...fields,
});

beforeEach(() => mock.restoreAll());

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

async function call(method, url, token, body) {
  const listener = app.listen(0);
  await new Promise((resolve) => listener.once('listening', resolve));
  try {
    const res = await globalThis.fetch(`http://127.0.0.1:${listener.address().port}${url}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    return { status: res.status, body: await res.json() };
  } finally {
    listener.closeAllConnections();
    await new Promise((resolve) => listener.close(resolve));
  }
}

function setUp({ listing, vendor, reserved = true, earlier = null, current } = {}) {
  mock.method(Order, 'findOne', async () => earlier);
  mock.method(Listing, 'findById', async () => current ?? listing ?? null);
  mock.method(Vendor, 'findById', async () => vendor ?? null);
  return {
    reserve: mock.method(Listing, 'findOneAndUpdate', async () => (reserved ? listing : null)),
    release: mock.method(Listing, 'updateOne', async () => ({})),
    create: mock.method(Order, 'create', async (fields) => ({ _id: 'o1', ...fields })),
  };
}

const orderBody = (listing, extra = {}) => ({
  listingId: String(listing._id),
  quantity: 2,
  requestId: 'request-0001',
  ...extra,
});

test('POST /api/orders returns 401 when not logged in', async () => {
  assert.equal((await call('POST', '/api/orders', null, {})).status, 401);
});

test('POST /api/orders returns 403 for other roles', async () => {
  for (const role of ['vendor', 'admin']) {
    const token = signedInAs(makeUser(role));
    assert.equal((await call('POST', '/api/orders', token, {})).status, 403, role);
    mock.restoreAll();
  }
});

test('POST /api/orders rejects a bad quantity with the agreed message', async () => {
  const token = signedInAs(makeUser('customer'));
  const { reserve } = setUp();
  for (const quantity of [0, -1, 1.5, '2', undefined, 1000]) {
    const res = await call('POST', '/api/orders', token, {
      listingId: 'x',
      quantity,
      requestId: 'request-0001',
    });
    assert.equal(res.status, 400);
    assert.equal(res.body.error, 'Choose a valid quantity.');
  }
  assert.equal(reserve.mock.callCount(), 0);
});

test('POST /api/orders needs a request ID', async () => {
  const token = signedInAs(makeUser('customer'));
  setUp();
  const res = await call('POST', '/api/orders', token, { listingId: 'x', quantity: 1 });
  assert.equal(res.status, 400);
});

test('POST /api/orders reduces stock and raises the sales count in one atomic update', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const { reserve } = setUp({ listing, vendor });

  const res = await call('POST', '/api/orders', token, orderBody(listing));

  assert.equal(res.status, 201);
  const [filter, update] = reserve.mock.calls[0].arguments;
  assert.equal(filter.status, 'active');
  assert.equal(filter.quantityAvailable.$gte, 2);
  assert.ok(filter.pickupEnd.$gt instanceof Date);
  assert.deepEqual(update.$inc, { quantityAvailable: -2, soldCount: 2 });
});

test('POST /api/orders copies values from the listing and ignores client values', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const { create } = setUp({ listing, vendor });

  await call('POST', '/api/orders', token, orderBody(listing, {
    unitPrice: 0.01,
    totalPrice: 0.01,
    status: 'completed',
    customer: 'someone-else',
    itemName: 'Free food',
  }));

  const fields = create.mock.calls[0].arguments[0];
  assert.equal(String(fields.customer), customer.id);
  assert.equal(String(fields.vendor), String(vendor._id));
  assert.equal(fields.itemName, 'Nasi Lemak');
  assert.equal(fields.category, 'Rice');
  assert.equal(fields.stallName, 'Warung Pak Din');
  assert.equal(fields.pickupAddress, 'Cafeteria A, UTM Skudai');
  assert.equal(fields.unitPrice, 4.55);
  assert.equal(fields.originalUnitPrice, 8);
  assert.equal(fields.totalPrice, 9.1);
  assert.equal(fields.pickupEnd, listing.pickupEnd);
  assert.equal(fields.status, undefined);
});

test('a new order defaults to pending', () => {
  assert.equal(new Order().status, 'pending');
});

test('POST /api/orders explains not having enough stock', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor, { quantityAvailable: 1 });
  const { create } = setUp({ listing, vendor, reserved: false });

  const res = await call('POST', '/api/orders', token, orderBody(listing));

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'NOT_ENOUGH_STOCK');
  assert.equal(res.body.available, 1);
  assert.equal(res.body.error, 'Only 1 Nasi Lemak left. Choose 1 or fewer and try again.');
  assert.equal(create.mock.callCount(), 0);
});

test('POST /api/orders explains a sold-out item', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor, { quantityAvailable: 0 });
  setUp({ listing, vendor, reserved: false });

  const res = await call('POST', '/api/orders', token, orderBody(listing));

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'SOLD_OUT');
  assert.equal(res.body.error, 'Sorry, Nasi Lemak has just sold out.');
});

test('POST /api/orders explains an ended pickup', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor, { pickupStart: hoursFromNow(-3), pickupEnd: hoursFromNow(-1) });
  setUp({ listing, vendor, reserved: false });

  const res = await call('POST', '/api/orders', token, orderBody(listing));

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'PICKUP_ENDED');
  assert.equal(res.body.error, 'Pickup for Nasi Lemak has ended.');
});

test('POST /api/orders returns 404 for a missing listing, vendor or invalid ID', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);

  for (const [state, listingId] of [
    [{}, String(new mongoose.Types.ObjectId())],
    [{ listing }, String(listing._id)],
    [{}, 'not-an-id'],
  ]) {
    setUp(state);
    const res = await call('POST', '/api/orders', token, { listingId, quantity: 1, requestId: 'request-0001' });
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'LISTING_GONE');
    assert.equal(res.body.error, 'This item is no longer available.');
    mock.restoreAll();
    signedInAs(makeUser('customer'));
  }
});

test('POST /api/orders puts stock back when saving the order fails', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const { release, create } = setUp({ listing, vendor });
  create.mock.mockImplementation(async () => {
    throw new Error('save failed');
  });
  mock.method(console, 'error', () => {});

  const res = await call('POST', '/api/orders', token, orderBody(listing));

  assert.equal(res.status, 500);
  assert.equal(res.body.error, "We couldn't place your order. Please try again.");
  assert.deepEqual(release.mock.calls[0].arguments[1].$inc, { quantityAvailable: 2, soldCount: -2 });
});

test('POST /api/orders returns the first order for a repeated request without touching stock', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const { reserve, create } = setUp({ listing, vendor, earlier: { _id: 'first-order' } });

  const res = await call('POST', '/api/orders', token, orderBody(listing));

  assert.equal(res.status, 200);
  assert.equal(res.body.order._id, 'first-order');
  assert.equal(reserve.mock.callCount(), 0);
  assert.equal(create.mock.callCount(), 0);
});

test('two requests racing with one request ID keep a single order and return the stock', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const { release, create } = setUp({ listing, vendor });
  create.mock.mockImplementation(async () => {
    throw Object.assign(new Error('duplicate'), { code: 11000 });
  });

  const res = await call('POST', '/api/orders', token, orderBody(listing));

  assert.equal(res.status, 200);
  assert.equal(release.mock.callCount(), 1);
});

test('GET /api/listings/:id is customer-only', async () => {
  const id = String(new mongoose.Types.ObjectId());
  assert.equal((await call('GET', `/api/listings/${id}`)).status, 401);
  for (const role of ['vendor', 'admin']) {
    const token = signedInAs(makeUser(role));
    assert.equal((await call('GET', `/api/listings/${id}`, token)).status, 403, role);
    mock.restoreAll();
  }
});

test('GET /api/listings/:id returns details without private vendor data', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  setUp({ listing, vendor });

  const res = await call('GET', `/api/listings/${listing._id}`, token);

  assert.equal(res.status, 200);
  assert.equal(res.body.listing.stallName, 'Warung Pak Din');
  assert.equal(res.body.listing.pickupAddress, 'Cafeteria A, UTM Skudai');
  assert.equal(res.body.listing.soldCount, 0);
  for (const hidden of ['vendor', 'user', 'phone', 'location']) {
    assert.equal(res.body.listing[hidden], undefined, hidden);
  }
});

test('GET /api/listings/:id returns 404 when the listing or vendor is gone', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);

  setUp({ listing });
  assert.equal((await call('GET', `/api/listings/${listing._id}`, token)).status, 404);
  mock.restoreAll();

  const again = signedInAs(makeUser('customer'));
  setUp({});
  assert.equal((await call('GET', '/api/listings/not-an-id', again)).status, 404);
});

test('GET /api/listings/:id still returns a sold-out listing so the app can explain it', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const listing = listingDoc(vendor, { quantityAvailable: 0 });
  setUp({ listing, vendor });

  const res = await call('GET', `/api/listings/${listing._id}`, token);

  assert.equal(res.status, 200);
  assert.equal(res.body.listing.quantityAvailable, 0);
});

test('a client cannot set soldCount when creating a listing', async () => {
  const token = signedInAs(makeUser('vendor'));
  const vendor = vendorDoc();
  mock.method(Vendor, 'findOne', async () => vendor);
  const create = mock.method(Listing, 'create', async (fields) => fields);

  const res = await call('POST', '/api/listings', token, {
    title: 'Nasi Lemak',
    category: 'Rice',
    isHalal: true,
    originalPrice: 8,
    discountedPrice: 4.5,
    quantityAvailable: 5,
    soldCount: 99,
    pickupStart: hoursFromNow(1).toISOString(),
    pickupEnd: hoursFromNow(3).toISOString(),
  });

  assert.equal(res.status, 201);
  assert.equal(create.mock.calls[0].arguments[0].soldCount, undefined);
});

test('seed orders add up to each sample listing soldCount', () => {
  const stalls = [vendorDoc(), vendorDoc(), vendorDoc()];
  const listings = sampleListings(stalls).map((fields) => new Listing(fields));
  const customers = [makeUser('customer'), makeUser('customer')];

  const orders = sampleOrders(customers, listings, stalls);

  assert.equal(orders.length, SAMPLE_ORDERS.length);
  for (const listing of listings) {
    const sold = orders
      .filter((order) => order.itemName === listing.title)
      .reduce((sum, order) => sum + order.quantity, 0);
    assert.equal(listing.soldCount, sold, listing.title);
  }
});

test('the seed cart has two stalls, to show the pickup warning', () => {
  const stalls = ['First', 'Second', 'Third'].map((stallName) => {
    const stall = vendorDoc();
    stall.stallName = stallName;
    return stall;
  });
  const listings = sampleListings(stalls).map((fields) => new Listing(fields));

  const { items } = sampleCart(makeUser('customer'), listings, stalls);

  assert.deepEqual(items.map((item) => item.stallName), ['First', 'Third']);
});
