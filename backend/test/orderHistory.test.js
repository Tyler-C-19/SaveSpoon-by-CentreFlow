// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const User = require('../src/models/User');
const Listing = require('../src/models/Listing');
const Vendor = require('../src/models/Vendor');
const Order = require('../src/models/Order');
const { signToken } = require('../src/services/tokenService');
const { orderTabQuery } = require('../src/services/orderService');
const { ORDER_NOT_FOUND, PAGE_SIZE } = require('../src/controllers/orderController');
const { sampleListings } = require('../seed/sampleListings');
const { sampleOrders } = require('../seed/sampleOrders');
const { call } = require('./testServer');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });

const newId = () => new mongoose.Types.ObjectId();

beforeEach(() => mock.restoreAll());

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

const orderRow = (fields = {}) => ({
  _id: newId(),
  itemName: 'Nasi Lemak',
  stallName: 'Warung Pak Din',
  quantity: 1,
  totalPrice: 4.5,
  status: 'pending',
  ...fields,
});

const listingRow = (vendor, fields = {}) => ({
  _id: newId(),
  title: 'Nasi Lemak',
  quantityAvailable: 3,
  vendor,
  ...fields,
});

for (const url of ['/api/orders', '/api/orders/again', `/api/orders/${newId()}`]) {
  test(`GET ${url.replace(/[a-f0-9]{24}$/, ':id')} is customer-only`, async () => {
    assert.equal((await call(url)).status, 401);
    for (const role of ['vendor', 'admin']) {
      const res = await call(url, { token: signedInAs(makeUser(role)) });
      assert.equal(res.status, 403, role);
    }
  });
}

test('GET /api/orders rejects an unknown tab or a bad page', async () => {
  const token = signedInAs(makeUser('customer'));
  const find = mock.method(Order, 'find', async () => []);

  assert.equal((await call('/api/orders?tab=past', { token })).status, 400);
  assert.equal((await call('/api/orders?page=0', { token })).status, 400);
  assert.equal((await call('/api/orders?page=abc', { token })).status, 400);
  assert.equal(find.mock.callCount(), 0);
});

test('Upcoming holds open orders whose pickup has not ended, soonest pickup first', () => {
  const now = new Date('2026-11-13T10:00:00Z');
  const customer = newId();

  const { filter, sort } = orderTabQuery('upcoming', customer, now);

  assert.deepEqual(filter, { customer, status: { $in: ['pending', 'confirmed'] }, pickupEnd: { $gt: now } });
  assert.deepEqual(sort, { pickupStart: 1, pickupEnd: 1, _id: 1 });
});

test('History holds finished and cancelled orders and open orders whose pickup has ended', () => {
  const now = new Date('2026-11-13T10:00:00Z');
  const customer = newId();

  const { filter, sort } = orderTabQuery('history', customer, now);

  assert.deepEqual(filter, {
    customer,
    $or: [{ status: { $nin: ['pending', 'confirmed'] } }, { pickupEnd: { $lte: now } }],
  });
  assert.deepEqual(sort, { createdAt: -1, _id: -1 });
});

test('All holds every order of the customer, newest first', () => {
  const customer = newId();

  assert.deepEqual(orderTabQuery('all', customer), { filter: { customer }, sort: { createdAt: -1, _id: -1 } });
});

test('GET /api/orders returns only the customer\'s own orders, 20 at a time', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const rows = Array.from({ length: PAGE_SIZE + 1 }, () => orderRow());
  const find = mock.method(Order, 'find', async () => rows);

  const res = await call('/api/orders?tab=upcoming&page=2', { token });

  assert.equal(res.status, 200);
  assert.equal(res.body.orders.length, PAGE_SIZE);
  assert.equal(res.body.hasMore, true);
  const [filter, fields, options] = find.mock.calls[0].arguments;
  assert.equal(String(filter.customer), customer.id);
  assert.deepEqual(filter.status, { $in: ['pending', 'confirmed'] });
  assert.equal(options.skip, PAGE_SIZE);
  assert.equal(options.limit, PAGE_SIZE + 1);
  assert.doesNotMatch(fields, /\bcustomer\b|\brequestId\b|\bvendor\b/);
});

test('GET /api/orders defaults to the All tab and says when there are no more', async () => {
  const token = signedInAs(makeUser('customer'));
  const find = mock.method(Order, 'find', async () => [orderRow()]);

  const res = await call('/api/orders', { token });

  assert.equal(res.status, 200);
  assert.equal(res.body.orders.length, 1);
  assert.equal(res.body.hasMore, false);
  assert.equal(find.mock.calls[0].arguments[0].$or, undefined);
  assert.equal(find.mock.calls[0].arguments[2].skip, 0);
});

test('GET /api/orders/:id returns the customer\'s own order', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow();
  const findOne = mock.method(Order, 'findOne', async () => order);

  const res = await call(`/api/orders/${order._id}`, { token });

  assert.equal(res.status, 200);
  assert.equal(res.body.order.itemName, 'Nasi Lemak');
  const [filter] = findOne.mock.calls[0].arguments;
  assert.equal(String(filter._id), String(order._id));
  assert.equal(String(filter.customer), customer.id);
});

test('GET /api/orders/:id returns 404 for another customer\'s order or a bad ID', async () => {
  const token = signedInAs(makeUser('customer'));
  const findOne = mock.method(Order, 'findOne', async () => null);

  const other = await call(`/api/orders/${newId()}`, { token });
  assert.equal(other.status, 404);
  assert.equal(other.body.error, ORDER_NOT_FOUND);

  const bad = await call('/api/orders/not-an-id', { token });
  assert.equal(bad.status, 404);
  assert.equal(findOne.mock.callCount(), 1);
});

test('GET /api/orders/again lists available items ordered before, most recent first', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const stall = newId();
  const gone = newId();
  const first = listingRow(stall, { title: 'Latest' });
  const second = listingRow(stall, { title: 'Earlier' });
  const noStall = listingRow(gone, { title: 'Stall deleted' });
  const aggregate = mock.method(Order, 'aggregate', async () => [
    { _id: first._id }, { _id: noStall._id }, { _id: second._id }, { _id: newId() },
  ]);
  const find = mock.method(Listing, 'find', async () => [second, noStall, first]);
  mock.method(Vendor, 'find', async () => [{ _id: stall, stallName: 'Warung Pak Din' }]);

  const res = await call('/api/orders/again', { token });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.listings.map((listing) => listing.title), ['Latest', 'Earlier']);
  assert.equal(res.body.listings[0].stallName, 'Warung Pak Din');
  assert.equal(res.body.listings[0].vendor, undefined);
  assert.equal(String(aggregate.mock.calls[0].arguments[0][0].$match.customer), customer.id);
  const [filter] = find.mock.calls[0].arguments;
  assert.equal(filter.status, 'active');
  assert.deepEqual(filter.quantityAvailable, { $gt: 0 });
  assert.ok(filter.pickupEnd.$gt instanceof Date);
});

test('GET /api/orders/again shows at most 6 and nothing for a customer with no orders', async () => {
  const token = signedInAs(makeUser('customer'));
  const stall = newId();
  const listings = Array.from({ length: 8 }, (_, index) => listingRow(stall, { title: `Item ${index}` }));
  const aggregate = mock.method(Order, 'aggregate', async () => listings.map(({ _id }) => ({ _id })));
  const find = mock.method(Listing, 'find', async () => listings);
  mock.method(Vendor, 'find', async () => [{ _id: stall, stallName: 'Warung Pak Din' }]);

  const res = await call('/api/orders/again', { token });
  assert.equal(res.body.listings.length, 6);
  assert.equal(res.body.listings[0].title, 'Item 0');

  aggregate.mock.mockImplementation(async () => []);
  const empty = await call('/api/orders/again', { token });
  assert.deepEqual(empty.body.listings, []);
  assert.equal(find.mock.callCount(), 1);
});

test('seed orders show every tab and status', () => {
  const stalls = [0, 1, 2].map(() => new Vendor({ user: newId(), stallName: 'Stall', address: 'Arked A' }));
  const listings = sampleListings(stalls).map((fields) => new Listing(fields));
  const customers = [makeUser('customer'), makeUser('customer')];
  const now = new Date();

  const orders = sampleOrders(customers, listings, stalls);
  const earlier = orders.filter((order) => order.pickupEnd <= now);

  assert.ok(orders.some((order) => !order.status && order.pickupEnd > now), 'upcoming');
  assert.deepEqual(earlier.map((order) => order.status).sort(), ['cancelled', 'completed', 'pending']);
  for (const order of earlier) assert.ok(order.createdAt < order.pickupStart);
});
