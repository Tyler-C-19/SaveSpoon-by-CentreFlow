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
const {
  cancelUntil, cancellableFilter, orderTabQuery, withCancelUntil, CANCEL_GRACE_MS, CANCEL_LIMIT,
} = require('../src/services/orderService');
const { CANCEL_REASON_ERROR } = require('../src/validators/orderValidators');
const { sampleListings } = require('../seed/sampleListings');
const { sampleOrders } = require('../seed/sampleOrders');
const { call } = require('./testServer');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });

const newId = () => new mongoose.Types.ObjectId();

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;

beforeEach(() => mock.restoreAll());

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

// An order whose pickup starts in an hour, placed ten minutes ago.
function orderRow(customer, fields = {}) {
  const now = Date.now();
  return {
    _id: newId(),
    customer,
    listing: newId(),
    vendor: newId(),
    requestId: 'request-123',
    itemName: 'Nasi Lemak',
    stallName: 'Warung Pak Din',
    quantity: 2,
    totalPrice: 9,
    status: 'pending',
    createdAt: new Date(now - 10 * MINUTE),
    pickupStart: new Date(now + HOUR),
    pickupEnd: new Date(now + 3 * HOUR),
    ...fields,
  };
}

// Mocks the order lookups. Orders listed in `stuck` fail the conditional cancel.
function mockOrders(rows, { stuck = [], recentCancels = [] } = {}) {
  const byId = new Map(rows.map((row) => [String(row._id), row]));
  const findOne = mock.method(Order, 'findOne', async (filter) => byId.get(String(filter._id)) ?? null);
  const aggregate = mock.method(Order, 'aggregate', async () => recentCancels);
  const update = mock.method(Order, 'findOneAndUpdate', async (filter, changes) => {
    const row = byId.get(String(filter._id));
    if (!row || stuck.includes(row)) return null;
    return { ...row, ...changes.$set };
  });
  const find = mock.method(Order, 'find', async (filter) =>
    rows.filter((row) => row.checkoutId === filter.checkoutId && String(row._id) !== String(filter._id.$ne)));
  const returnStock = mock.method(Listing, 'updateOne', async () => ({ matchedCount: 1, modifiedCount: 1 }));
  return { findOne, aggregate, update, find, returnStock };
}

test('POST /api/orders/:id/cancel is customer-only', async () => {
  const url = `/api/orders/${newId()}/cancel`;
  assert.equal((await call(url, { method: 'POST', body: {} })).status, 401);
  for (const role of ['vendor', 'admin']) {
    const res = await call(url, { method: 'POST', body: {}, token: signedInAs(makeUser(role)) });
    assert.equal(res.status, 403, role);
  }
});

test('cancelling another customer\'s order or a bad ID returns 404', async () => {
  const token = signedInAs(makeUser('customer'));
  const { findOne, update } = mockOrders([]);

  assert.equal((await call(`/api/orders/${newId()}/cancel`, { method: 'POST', body: {}, token })).status, 404);
  assert.equal((await call('/api/orders/not-an-id/cancel', { method: 'POST', body: {}, token })).status, 404);
  assert.equal(findOne.mock.callCount(), 1);
  assert.equal(update.mock.callCount(), 0);
});

test('an unknown reason or a non-boolean wholeCheckout is rejected', async () => {
  const token = signedInAs(makeUser('customer'));
  const { findOne } = mockOrders([]);
  const url = `/api/orders/${newId()}/cancel`;

  const reason = await call(url, { method: 'POST', body: { reason: 'too spicy' }, token });
  assert.equal(reason.status, 400);
  assert.equal(reason.body.error, CANCEL_REASON_ERROR);
  assert.equal((await call(url, { method: 'POST', body: { wholeCheckout: 'yes' }, token })).status, 400);
  assert.equal(findOne.mock.callCount(), 0);
});

test('an order can be cancelled until pickup starts', () => {
  const now = new Date('2026-11-14T10:00:00Z');
  const order = {
    status: 'pending',
    createdAt: new Date('2026-11-14T08:00:00Z'),
    pickupStart: new Date('2026-11-14T11:00:00Z'),
    pickupEnd: new Date('2026-11-14T13:00:00Z'),
  };

  assert.deepEqual(cancelUntil(order, now), order.pickupStart);
  assert.deepEqual(cancelUntil({ ...order, status: 'confirmed' }, now), order.pickupStart);
  assert.equal(cancelUntil(order, new Date('2026-11-14T11:00:00Z')), null);
  assert.equal(cancelUntil({ ...order, status: 'completed' }, now), null);
  assert.equal(cancelUntil({ ...order, status: 'cancelled' }, now), null);
});

test('an order placed during pickup can be cancelled for 5 minutes, never after pickup ends', () => {
  const placed = new Date('2026-11-14T12:00:00Z');
  const order = {
    status: 'pending',
    createdAt: placed,
    pickupStart: new Date('2026-11-14T11:00:00Z'),
    pickupEnd: new Date('2026-11-14T13:00:00Z'),
  };

  assert.deepEqual(cancelUntil(order, placed), new Date(placed.getTime() + CANCEL_GRACE_MS));
  assert.equal(cancelUntil(order, new Date(placed.getTime() + CANCEL_GRACE_MS)), null);

  const nearEnd = { ...order, pickupEnd: new Date(placed.getTime() + 2 * MINUTE) };
  assert.deepEqual(cancelUntil(nearEnd, placed), nearEnd.pickupEnd);
});

test('the cancel filter matches the same rule as cancelUntil', () => {
  const now = new Date('2026-11-14T10:00:00Z');

  assert.deepEqual(cancellableFilter(now), {
    status: { $in: ['pending', 'confirmed'] },
    pickupEnd: { $gt: now },
    $or: [
      { pickupStart: { $gt: now } },
      { createdAt: { $gt: new Date(now.getTime() - CANCEL_GRACE_MS) } },
    ],
  });
});

test('cancelling returns the stock to the order\'s own round and records who and why', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow(customer._id);
  const { update, returnStock } = mockOrders([order]);

  const res = await call(`/api/orders/${order._id}/cancel`, {
    method: 'POST', body: { reason: 'ordered_by_mistake' }, token,
  });

  assert.equal(res.status, 200);
  assert.equal(res.body.cancelled.length, 1);
  assert.equal(res.body.cancelled[0].status, 'cancelled');
  assert.equal(res.body.cancelled[0].customer, undefined);
  assert.equal(res.body.cancelled[0].requestId, undefined);
  assert.deepEqual(res.body.skipped, []);

  const [filter, changes] = update.mock.calls[0].arguments;
  assert.equal(String(filter.customer), customer.id);
  assert.deepEqual(filter.status, { $in: ['pending', 'confirmed'] });
  assert.equal(changes.$set.status, 'cancelled');
  assert.equal(changes.$set.cancelledBy, 'customer');
  assert.equal(changes.$set.cancelReason, 'ordered_by_mistake');
  assert.ok(changes.$set.cancelledAt instanceof Date);

  const [listingFilter, stock] = returnStock.mock.calls[0].arguments;
  assert.equal(String(listingFilter._id), String(order.listing));
  assert.deepEqual(listingFilter.pickupEnd, order.pickupEnd);
  assert.deepEqual(listingFilter.soldCount, { $gte: 2 });
  assert.deepEqual(stock.$inc, { quantityAvailable: 2, soldCount: -2 });
});

test('a cancel with no reason leaves the reason empty', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow(customer._id);
  const { update } = mockOrders([order]);

  const res = await call(`/api/orders/${order._id}/cancel`, { method: 'POST', body: {}, token });

  assert.equal(res.status, 200);
  assert.equal('cancelReason' in update.mock.calls[0].arguments[1].$set, false);
});

test('the order still cancels when its listing is gone or has moved to a later round', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow(customer._id);
  const { returnStock } = mockOrders([order]);
  returnStock.mock.mockImplementation(async () => ({ matchedCount: 0, modifiedCount: 0 }));

  const res = await call(`/api/orders/${order._id}/cancel`, { method: 'POST', body: {}, token });

  assert.equal(res.status, 200);
  assert.equal(res.body.cancelled[0].status, 'cancelled');
});

test('a closed order explains why and changes nothing', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const now = Date.now();
  const cases = [
    [orderRow(customer._id, { status: 'cancelled' }), 'ALREADY_CANCELLED'],
    [orderRow(customer._id, { status: 'completed' }), 'ORDER_COMPLETED'],
    [orderRow(customer._id, { pickupStart: new Date(now - HOUR) }), 'PICKUP_STARTED'],
    [orderRow(customer._id, { pickupStart: new Date(now - 3 * HOUR), pickupEnd: new Date(now - HOUR) }), 'PICKUP_ENDED'],
  ];
  const { update, returnStock } = mockOrders(cases.map(([order]) => order));

  for (const [order, code] of cases) {
    const res = await call(`/api/orders/${order._id}/cancel`, { method: 'POST', body: {}, token });
    assert.equal(res.status, 409, code);
    assert.equal(res.body.code, code);
    assert.ok(res.body.error);
  }
  assert.equal(update.mock.callCount(), 0);
  assert.equal(returnStock.mock.callCount(), 0);
});

test('an order placed during pickup can be cancelled within the grace period', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const now = Date.now();
  const order = orderRow(customer._id, { createdAt: new Date(now - MINUTE), pickupStart: new Date(now - HOUR) });
  mockOrders([order]);

  const res = await call(`/api/orders/${order._id}/cancel`, { method: 'POST', body: {}, token });

  assert.equal(res.status, 200);
});

test('a repeated request returns no stock twice', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow(customer._id);
  const { returnStock } = mockOrders([order], { stuck: [order] });

  const res = await call(`/api/orders/${order._id}/cancel`, { method: 'POST', body: {}, token });

  assert.equal(res.status, 409);
  assert.equal(returnStock.mock.callCount(), 0);
});

test('cancelling a whole checkout skips orders that can no longer be cancelled', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow(customer._id, { checkoutId: 'checkout-1' });
  const other = orderRow(customer._id, { checkoutId: 'checkout-1', itemName: 'Kuih' });
  const started = orderRow(customer._id, { checkoutId: 'checkout-1', itemName: 'Teh Tarik' });
  const { find, returnStock } = mockOrders([order, other, started], { stuck: [started] });

  const res = await call(`/api/orders/${order._id}/cancel`, {
    method: 'POST', body: { wholeCheckout: true }, token,
  });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.cancelled.map((item) => item.itemName), ['Nasi Lemak', 'Kuih']);
  assert.deepEqual(res.body.skipped.map((item) => item.itemName), ['Teh Tarik']);
  assert.equal(returnStock.mock.callCount(), 2);
  const [filter] = find.mock.calls[0].arguments;
  assert.equal(String(filter.customer), customer.id);
  assert.deepEqual(filter.status, { $in: ['pending', 'confirmed'] });
});

test('without wholeCheckout only the one order is cancelled', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow(customer._id, { checkoutId: 'checkout-1' });
  const { find } = mockOrders([order, orderRow(customer._id, { checkoutId: 'checkout-1' })]);

  const res = await call(`/api/orders/${order._id}/cancel`, { method: 'POST', body: {}, token });

  assert.equal(res.body.cancelled.length, 1);
  assert.equal(find.mock.callCount(), 0);
});

test('a customer can cancel 5 times in 24 hours', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow(customer._id);
  const now = Date.now();
  const recentCancels = Array.from({ length: CANCEL_LIMIT }, (_, index) => ({ _id: new Date(now - index * HOUR) }));
  const { aggregate, update } = mockOrders([order], { recentCancels });

  const res = await call(`/api/orders/${order._id}/cancel`, { method: 'POST', body: {}, token });

  assert.equal(res.status, 429);
  assert.equal(res.body.code, 'CANCEL_LIMIT');
  assert.match(res.body.error, /5 times in 24 hours.*about 20 hours/);
  assert.equal(update.mock.callCount(), 0);
  const [match, group] = aggregate.mock.calls[0].arguments[0];
  assert.equal(String(match.$match.customer), customer.id);
  assert.equal(match.$match.cancelledBy, 'customer');
  assert.deepEqual(group, { $group: { _id: '$cancelledAt' } });
});

test('fewer than 5 recent cancels still allows cancelling', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const order = orderRow(customer._id);
  const recentCancels = Array.from({ length: CANCEL_LIMIT - 1 }, () => ({ _id: new Date() }));
  mockOrders([order], { recentCancels });

  const res = await call(`/api/orders/${order._id}/cancel`, { method: 'POST', body: {}, token });

  assert.equal(res.status, 200);
});

test('GET /api/orders/:id says until when it can be cancelled and lists the rest of its checkout', async () => {
  const customer = makeUser('customer');
  const token = signedInAs(customer);
  const { customer: owner, ...order } = orderRow(customer._id, { checkoutId: 'checkout-1' });
  const now = Date.now();
  const kuih = orderRow(customer._id, { itemName: 'Kuih', quantity: 1 });
  const started = orderRow(customer._id, { itemName: 'Teh Tarik', pickupStart: new Date(now - HOUR) });
  mock.method(Order, 'findOne', async () => order);
  const find = mock.method(Order, 'find', async () => [kuih, started]);

  const res = await call(`/api/orders/${order._id}`, { token });

  assert.equal(res.status, 200);
  assert.equal(res.body.order.cancelUntil, order.pickupStart.toISOString());
  assert.deepEqual(
    res.body.order.checkoutOrders.map(({ itemName, quantity, stallName, canCancel }) => [itemName, quantity, stallName, canCancel]),
    [['Kuih', 1, 'Warung Pak Din', true], ['Teh Tarik', 2, 'Warung Pak Din', false]]
  );
  assert.equal(res.body.order.checkoutOrders[0].customer, undefined);
  assert.equal(res.body.order.otherCancellable, 1);
  const [filter, fields] = find.mock.calls[0].arguments;
  assert.equal(String(filter.customer), customer.id);
  assert.equal(filter.checkoutId, 'checkout-1');
  assert.deepEqual(filter.status, { $in: ['pending', 'confirmed'] });
  assert.doesNotMatch(fields, /customer|requestId/);
});

test('GET /api/orders/:id shows no cancel time for a closed order', async () => {
  const token = signedInAs(makeUser('customer'));
  const order = orderRow(newId(), { status: 'completed', checkoutId: 'checkout-1' });
  mock.method(Order, 'findOne', async () => order);
  const find = mock.method(Order, 'find', async () => []);

  const res = await call(`/api/orders/${order._id}`, { token });

  assert.equal(res.body.order.cancelUntil, null);
  assert.deepEqual(res.body.order.checkoutOrders, []);
  assert.equal(res.body.order.otherCancellable, 0);
  assert.equal(find.mock.callCount(), 0);
});

test('the Cancelled tab holds only cancelled orders, newest placed first', () => {
  const customer = newId();

  assert.deepEqual(orderTabQuery('cancelled', customer), {
    filter: { customer, status: 'cancelled' },
    sort: { createdAt: -1, _id: -1 },
  });
});

test('GET /api/orders accepts the Cancelled tab', async () => {
  const token = signedInAs(makeUser('customer'));
  const find = mock.method(Order, 'find', async () => []);

  const res = await call('/api/orders?tab=cancelled', { token });

  assert.equal(res.status, 200);
  assert.equal(find.mock.calls[0].arguments[0].status, 'cancelled');
});

test('the seed\'s cancelled order says when and by whom', () => {
  const stalls = [0, 1, 2].map(() => new Vendor({ user: newId(), stallName: 'Stall', address: 'Arked A' }));
  const listings = sampleListings(stalls).map((fields) => new Listing(fields));
  const customers = [makeUser('customer'), makeUser('customer')];

  const cancelled = sampleOrders(customers, listings, stalls).filter((order) => order.status === 'cancelled');

  assert.equal(cancelled.length, 1);
  for (const order of cancelled) {
    assert.equal(order.cancelledBy, 'customer');
    assert.ok(order.cancelledAt > order.createdAt && order.cancelledAt < order.pickupStart);
    assert.ok(new Order(order).validateSync() === undefined);
  }
});

test('new orders come back with their cancel deadline', () => {
  const now = new Date('2026-11-14T10:00:00Z');
  const order = new Order({
    customer: newId(),
    vendor: newId(),
    listing: newId(),
    requestId: 'request-123',
    itemName: 'Nasi Lemak',
    stallName: 'Warung Pak Din',
    pickupStart: new Date('2026-11-14T11:00:00Z'),
    pickupEnd: new Date('2026-11-14T13:00:00Z'),
    quantity: 1,
    unitPrice: 4.5,
    originalUnitPrice: 8,
    totalPrice: 4.5,
  });
  order.createdAt = now;

  const sent = withCancelUntil(order, now);

  assert.deepEqual(sent.cancelUntil, order.pickupStart);
  assert.equal(sent.itemName, 'Nasi Lemak');
  assert.equal(withCancelUntil({ ...sent, status: 'cancelled' }, now).cancelUntil, null);
});
