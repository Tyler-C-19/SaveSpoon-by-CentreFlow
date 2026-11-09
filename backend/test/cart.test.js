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
const Cart = require('../src/models/Cart');
const { signToken } = require('../src/services/tokenService');
const { distanceKm } = require('../src/services/cartService');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });

const hoursFromNow = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000);

const vendorDoc = (stallName = 'Warung Pak Din', coordinates = [103.6385, 1.559]) => new Vendor({
  user: new mongoose.Types.ObjectId(),
  stallName,
  address: `${stallName} address`,
  location: { type: 'Point', coordinates },
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
  location: { type: 'Point', coordinates: vendor.location.coordinates },
  ...fields,
});

const cartDoc = (customer, entries = []) => new Cart({
  customer: customer._id,
  items: entries.map(({ listing, stallName = 'Warung Pak Din', quantity = 1, price }) => ({
    listing: listing._id,
    quantity,
    itemName: listing.title,
    stallName,
    unitPriceWhenAdded: price ?? listing.discountedPrice,
  })),
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

function setUp({ cart = null, listings = [], vendors = [] } = {}) {
  mock.method(Cart, 'findOne', async () => cart);
  mock.method(Cart, 'findOneAndUpdate', async () => cart);
  mock.method(Listing, 'find', async () => listings);
  mock.method(Vendor, 'find', async () => vendors);
  mock.method(Listing, 'findById', async () => listings[0] ?? null);
  mock.method(Vendor, 'findById', async () => vendors[0] ?? null);
  if (cart) mock.method(cart, 'save', async () => cart);
}

for (const [method, url] of [
  ['GET', '/api/cart'],
  ['DELETE', '/api/cart'],
  ['POST', '/api/cart/items'],
  ['DELETE', '/api/cart/unavailable'],
  ['POST', '/api/cart/checkout'],
]) {
  test(`${method} ${url} is customer-only`, async () => {
    assert.equal((await call(method, url)).status, 401);
    for (const role of ['vendor', 'admin']) {
      const token = signedInAs(makeUser(role));
      assert.equal((await call(method, url, token)).status, 403, role);
      mock.restoreAll();
    }
  });
}

test('GET /api/cart returns an empty cart without creating one', async () => {
  const token = signedInAs(makeUser('customer'));
  setUp();
  const res = await call('GET', '/api/cart', token);
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.cart, { items: [], total: 0, warnings: [] });
  assert.equal(Cart.findOneAndUpdate.mock.callCount(), 0);
});

test('adding an item saves copies and the price', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const cart = cartDoc(customer);
  setUp({ cart, listings: [listing], vendors: [vendor] });

  const res = await call('POST', '/api/cart/items', token, { listingId: String(listing._id), quantity: 2 });

  assert.equal(res.status, 200);
  assert.equal(res.body.message, 'Added 2 x Nasi Lemak to your cart.');
  assert.equal(cart.items[0].quantity, 2);
  assert.equal(cart.items[0].itemName, 'Nasi Lemak');
  assert.equal(cart.items[0].stallName, 'Warung Pak Din');
  assert.equal(cart.items[0].unitPriceWhenAdded, 4.5);
  assert.equal(res.body.cart.total, 9);
});

test('adding the same item merges quantities up to the stock left', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const cart = cartDoc(customer, [{ listing, quantity: 4 }]);
  setUp({ cart, listings: [listing], vendors: [vendor] });

  const res = await call('POST', '/api/cart/items', token, { listingId: String(listing._id), quantity: 3 });

  assert.equal(cart.items.length, 1);
  assert.equal(cart.items[0].quantity, 5);
  assert.equal(res.body.message, 'Only 5 Nasi Lemak left, so your cart now has 5.');
});

test('adding stops at 20 different items', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const others = Array.from({ length: 20 }, () => ({ listing: listingDoc(vendor) }));
  setUp({ cart: cartDoc(customer, others), listings: [listing], vendors: [vendor] });

  const res = await call('POST', '/api/cart/items', token, { listingId: String(listing._id), quantity: 1 });

  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'Your cart is full (20 items). Remove something to add more.');
});

test('adding more of an item already in the cart says how many there are now', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  setUp({ cart: cartDoc(customer, [{ listing, quantity: 2 }]), listings: [listing], vendors: [vendor] });

  const res = await call('POST', '/api/cart/items', token, { listingId: String(listing._id), quantity: 1 });

  assert.equal(res.body.message, 'Added 1 more Nasi Lemak. Your cart now has 3.');
});

test('checkout names an item that sold out at the last moment', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const { two } = twoItemCart(customer);
  checkoutMocks({ failOn: two._id });
  const current = new Listing({ ...two.toObject(), quantityAvailable: 0 });
  mock.method(Listing, 'findById', async () => current);

  const res = await call('POST', '/api/cart/checkout', token, checkoutBody());

  assert.equal(
    res.body.error,
    'Nasi Lemak just sold out, so nothing was ordered. Check your cart and try again.'
  );
});

test('adding an unavailable item explains why', async () => {
  const token = signedInAs(makeUser('customer'));
  const vendor = vendorDoc();
  const soldOut = listingDoc(vendor, { quantityAvailable: 0 });
  setUp({ listings: [soldOut], vendors: [vendor] });

  const res = await call('POST', '/api/cart/items', token, { listingId: String(soldOut._id), quantity: 1 });

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'SOLD_OUT');
});

test('the cart flags unavailable items and leaves them out of the total', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const live = listingDoc(vendor);
  const soldOut = listingDoc(vendor, { title: 'Sold', quantityAvailable: 0 });
  const ended = listingDoc(vendor, { title: 'Ended', pickupStart: hoursFromNow(-3), pickupEnd: hoursFromNow(-1) });
  const deleted = listingDoc(vendor, { title: 'Deleted' });
  const cart = cartDoc(customer, [
    { listing: live, quantity: 2 },
    { listing: soldOut },
    { listing: ended },
    { listing: deleted },
  ]);
  setUp({ cart, listings: [live, soldOut, ended], vendors: [vendor] });

  const { body } = await call('GET', '/api/cart', token);

  assert.equal(body.cart.total, 9);
  assert.equal(body.cart.items[0].category, 'Rice');
  assert.equal(body.cart.items[0].pickupAddress, 'Warung Pak Din address');
  assert.equal(body.cart.items[3].category, null);
  assert.deepEqual(body.cart.items.map((item) => item.reason), [
    null,
    'Sold out',
    'Pickup ended',
    'No longer available',
  ]);
  assert.equal(body.cart.items[3].itemName, 'Deleted');
  assert.deepEqual(body.cart.items.map((item) => item.available), [true, false, false, false]);
});

test('the cart treats an item whose vendor is gone as no longer available', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  setUp({ cart: cartDoc(customer, [{ listing }]), listings: [listing], vendors: [] });

  const { body } = await call('GET', '/api/cart', token);

  assert.equal(body.cart.items[0].reason, 'No longer available');
  assert.equal(body.cart.total, 0);
});

test('the cart lowers a quantity above stock, saves it and says so', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor, { quantityAvailable: 2 });
  const cart = cartDoc(customer, [{ listing, quantity: 4 }]);
  setUp({ cart, listings: [listing], vendors: [vendor] });

  const { body } = await call('GET', '/api/cart', token);

  assert.equal(body.cart.items[0].quantity, 2);
  assert.equal(body.cart.items[0].notices[0], 'Only 2 left, so your quantity is now 2.');
  assert.equal(cart.save.mock.callCount(), 1);
});

test('the cart shows a changed price with a notice', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  setUp({ cart: cartDoc(customer, [{ listing, price: 3 }]), listings: [listing], vendors: [vendor] });

  const { body } = await call('GET', '/api/cart', token);

  assert.equal(body.cart.items[0].unitPrice, 4.5);
  assert.equal(body.cart.items[0].notices[0], 'Price changed from RM 3.00 to RM 4.50.');
  assert.equal(body.cart.total, 4.5);
});

test('the cart warns about separate pickup spots and times that do not overlap', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const first = vendorDoc('First', [103.6385, 1.559]);
  const second = vendorDoc('Second', [103.641, 1.5565]);
  const morning = listingDoc(first, { pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(2) });
  const evening = listingDoc(second, { pickupStart: hoursFromNow(3), pickupEnd: hoursFromNow(4) });
  setUp({
    cart: cartDoc(customer, [{ listing: morning }, { listing: evening }]),
    listings: [morning, evening],
    vendors: [first, second],
  });

  const { body } = await call('GET', '/api/cart', token);

  assert.equal(body.cart.warnings.length, 2);
  assert.equal(body.cart.warnings[0], "Heads up: you'll collect from 2 stalls, up to 0.4 km apart.");
  assert.equal(
    body.cart.warnings[1],
    "Heads up: these pickup times don't overlap, so you'll need more than one trip."
  );
});

test('times that overlap for only part of their windows show no time warning', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const long = listingDoc(vendor, { pickupStart: hoursFromNow(-1), pickupEnd: hoursFromNow(18) });
  const short = listingDoc(vendor, { pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(2) });
  setUp({
    cart: cartDoc(customer, [{ listing: long }, { listing: short }]),
    listings: [long, short],
    vendors: [vendor],
  });

  const { body } = await call('GET', '/api/cart', token);

  assert.deepEqual(body.cart.warnings, []);
});

test('one stall with overlapping times shows no warning', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const first = listingDoc(vendor);
  const second = listingDoc(vendor);
  setUp({
    cart: cartDoc(customer, [{ listing: first }, { listing: second }]),
    listings: [first, second],
    vendors: [vendor],
  });

  const { body } = await call('GET', '/api/cart', token);

  assert.deepEqual(body.cart.warnings, []);
});

test('distance is straight-line and takes coordinates as [lng, lat]', () => {
  assert.ok(Math.abs(distanceKm([0, 0], [0, 1]) - 111.19) < 0.1);
});

test('changing a quantity validates it and rejects an item not in the cart', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const listing = listingDoc(vendor);
  const cart = cartDoc(customer, [{ listing, quantity: 1 }]);
  setUp({ cart, listings: [listing], vendors: [vendor] });

  const url = `/api/cart/items/${listing._id}`;
  assert.equal((await call('PATCH', url, token, { quantity: 0 })).status, 400);
  assert.equal((await call('PATCH', `/api/cart/items/${new mongoose.Types.ObjectId()}`, token, { quantity: 1 })).status, 404);

  const res = await call('PATCH', url, token, { quantity: 3 });
  assert.equal(res.status, 200);
  assert.equal(cart.items[0].quantity, 3);
});

test('remove, remove unavailable and clear change only what they should', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const vendor = vendorDoc();
  const first = listingDoc(vendor);
  const second = listingDoc(vendor);
  const soldOut = listingDoc(vendor, { quantityAvailable: 0 });
  const cart = cartDoc(customer, [{ listing: first }, { listing: second }, { listing: soldOut }]);
  setUp({ cart, listings: [first, second, soldOut], vendors: [vendor] });

  await call('DELETE', '/api/cart/unavailable', token);
  assert.equal(cart.items.length, 2);

  await call('DELETE', `/api/cart/items/${first._id}`, token);
  assert.deepEqual(cart.items.map((item) => String(item.listing)), [String(second._id)]);

  await call('DELETE', '/api/cart', token);
  assert.equal(cart.items.length, 0);
});

function checkoutMocks({ earlier = [], failOn = null, insertFails = false } = {}) {
  mock.method(Order, 'find', async () => earlier);
  const reserve = mock.method(Listing, 'findOneAndUpdate', async (filter) =>
    String(filter._id) === String(failOn) ? null : { _id: filter._id });
  const release = mock.method(Listing, 'updateOne', async () => ({}));
  const remove = mock.method(Order, 'deleteMany', async () => ({}));
  const insert = mock.method(Order, 'insertMany', async (rows) => {
    if (insertFails) throw new Error('insert failed');
    return rows;
  });
  return { reserve, release, remove, insert };
}

function twoItemCart(customer) {
  const first = vendorDoc('First', [103.6385, 1.559]);
  const second = vendorDoc('Second', [103.641, 1.5565]);
  const one = listingDoc(first);
  const two = listingDoc(second);
  const soldOut = listingDoc(first, { quantityAvailable: 0 });
  const cart = cartDoc(customer, [
    { listing: one, stallName: 'First' },
    { listing: two, stallName: 'Second', quantity: 2 },
    { listing: soldOut, stallName: 'First' },
  ]);
  setUp({ cart, listings: [one, two, soldOut], vendors: [first, second] });
  return { cart, one, two, soldOut };
}

const checkoutBody = (expectedTotal = 13.5) => ({ requestId: 'checkout-0001', expectedTotal });

test('checkout creates one order per listing with a shared checkout ID', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const { cart, one, two, soldOut } = twoItemCart(customer);
  const { insert } = checkoutMocks();

  const res = await call('POST', '/api/cart/checkout', token, checkoutBody());

  assert.equal(res.status, 201);
  const rows = insert.mock.calls[0].arguments[0];
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map((row) => row.checkoutId), ['checkout-0001', 'checkout-0001']);
  assert.deepEqual(rows.map((row) => row.requestId), [
    `checkout-0001:${one._id}`,
    `checkout-0001:${two._id}`,
  ]);
  assert.deepEqual(rows.map((row) => row.stallName), ['First', 'Second']);
  assert.deepEqual(rows.map((row) => row.totalPrice), [4.5, 9]);
  assert.deepEqual(cart.items.map((item) => String(item.listing)), [String(soldOut._id)]);
});

test('checkout places nothing when the total changed', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const { cart } = twoItemCart(customer);
  const { reserve, insert } = checkoutMocks();

  const res = await call('POST', '/api/cart/checkout', token, checkoutBody(10));

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'CART_CHANGED');
  assert.equal(res.body.error, 'Your cart changed. The new total is RM 13.50. Check it and try again.');
  assert.equal(reserve.mock.callCount(), 0);
  assert.equal(insert.mock.callCount(), 0);
  assert.equal(cart.items.length, 3);
});

test('checkout is all or nothing when an item sells out at the last moment', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const { cart, one, two } = twoItemCart(customer);
  const { release, insert } = checkoutMocks({ failOn: two._id });
  const current = new Listing({ ...two.toObject(), quantityAvailable: 1 });
  mock.method(Listing, 'findById', async () => current);

  const res = await call('POST', '/api/cart/checkout', token, checkoutBody());

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'CART_CHANGED');
  assert.equal(
    res.body.error,
    'Only 1 Nasi Lemak left, so nothing was ordered. Check your cart and try again.'
  );
  assert.equal(insert.mock.callCount(), 0);
  assert.equal(release.mock.callCount(), 1);
  const [filter, update] = release.mock.calls[0].arguments;
  assert.equal(String(filter._id), String(one._id));
  assert.deepEqual(update.$inc, { quantityAvailable: 1, soldCount: -1 });
  assert.equal(cart.items.length, 3);
});

test('checkout returns all stock when saving the orders fails', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const { cart } = twoItemCart(customer);
  const { release, remove } = checkoutMocks({ insertFails: true });
  mock.method(console, 'error', () => {});

  const res = await call('POST', '/api/cart/checkout', token, checkoutBody());

  assert.equal(res.status, 500);
  assert.equal(res.body.error, "We couldn't place your order. Please try again.");
  assert.equal(release.mock.callCount(), 2);
  assert.equal(remove.mock.callCount(), 1);
  assert.equal(cart.items.length, 3);
});

test('a repeated checkout returns the first orders without touching stock', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  twoItemCart(customer);
  const { reserve } = checkoutMocks({ earlier: [{ _id: 'first' }] });

  const res = await call('POST', '/api/cart/checkout', token, checkoutBody());

  assert.equal(res.status, 200);
  assert.equal(res.body.orders[0]._id, 'first');
  assert.equal(reserve.mock.callCount(), 0);
});

test('checkout says so when nothing is available', async () => {
  const token = signedInAs(makeUser('customer'));
  setUp();
  checkoutMocks();

  const res = await call('POST', '/api/cart/checkout', token, checkoutBody(0));

  assert.equal(res.status, 409);
  assert.equal(res.body.error, 'None of the items in your cart can be ordered right now.');
});

test('checkout needs a request ID and total', async () => {
  const token = signedInAs(makeUser('customer'));
  setUp();
  assert.equal((await call('POST', '/api/cart/checkout', token, { expectedTotal: 1 })).status, 400);
  assert.equal((await call('POST', '/api/cart/checkout', token, { requestId: 'checkout-0001' })).status, 400);
});
