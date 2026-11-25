// These tests replace database calls and Firebase with mocks; nothing reaches the shared database
// and no real push is sent.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Order = require('../src/models/Order');
const Listing = require('../src/models/Listing');
const Favourite = require('../src/models/Favourite');
const Notification = require('../src/models/Notification');
const notifications = require('../src/services/notificationService');
const pushService = require('../src/services/pushService');
const orderService = require('../src/services/orderService');
const { signToken } = require('../src/services/tokenService');

const id = () => new mongoose.Types.ObjectId();
// 09:00 to 10:00 UTC is 5:00 PM to 6:00 PM in Malaysia.
const START = new Date('2026-11-20T09:00:00Z');
const END = new Date('2026-11-20T10:00:00Z');
const NOW = new Date('2026-11-20T07:00:00Z');

const vendorA = id();
const vendorB = id();
const vendorUserA = id();
const vendorUserB = id();
const customer = id();

let saved;
let pushes;
let pulled;
let users;

const order = (fields) => ({
  _id: id(), customer, vendor: vendorA, listing: 'l1', itemName: 'Nasi Lemak', quantity: 2,
  stallName: 'Warung Pak Din', pickupStart: START, pickupEnd: END, ...fields,
});

function selectable(value) {
  return { select: async () => value };
}

beforeEach(() => {
  mock.restoreAll();
  saved = [];
  pushes = [];
  pulled = [];
  users = [
    { _id: vendorUserA, deviceTokens: ['a-phone'], notificationPrefs: { orderAlerts: true } },
    { _id: vendorUserB, deviceTokens: ['b-phone'], notificationPrefs: { orderAlerts: true } },
    { _id: customer, deviceTokens: ['c-phone'], notificationPrefs: {} },
  ];
  mock.method(Vendor, 'find', () => selectable([{ _id: vendorA, user: vendorUserA }, { _id: vendorB, user: vendorUserB }]));
  mock.method(Notification, 'insertMany', async (docs) => {
    const withIds = docs.map((doc) => ({ _id: id(), ...doc }));
    saved.push(...withIds);
    return withIds;
  });
  mock.method(User, 'find', (filter) => selectable(
    users.filter((user) => filter._id.$in.map(String).includes(String(user._id)))
  ));
  mock.method(User, 'updateOne', async (filter, change) => pulled.push([filter, change]));
  mock.method(pushService, 'sendToTokens', async (tokens, message) => {
    pushes.push({ tokens, message });
    return [];
  });
  mock.method(Listing, 'find', () => selectable([]));
});

test('a checkout sends one alert per vendor and a silent re-sync to the customer', async () => {
  await notifications.orderPlaced([
    order({ itemName: 'Nasi Lemak', quantity: 2 }),
    order({ itemName: 'Kuih Box', quantity: 1, listing: 'l2' }),
    order({ vendor: vendorB, itemName: 'Teh Tarik', quantity: 1, listing: 'l3' }),
  ]);

  assert.equal(saved.length, 2);
  const [first, second] = saved;
  assert.equal(String(first.user), String(vendorUserA));
  assert.equal(first.title, '2 new orders received');
  assert.match(first.body, /^2 x Nasi Lemak and 1 x Kuih Box, pickup (today|tomorrow|\d+ \w+) 5:00–6:00 PM\.$/);
  assert.equal(first.listingId, undefined);
  assert.equal(second.title, 'New order received');
  assert.equal(second.listingId, 'l3');

  const visible = pushes.filter((push) => !push.message.silent);
  assert.deepEqual(visible.map((push) => push.tokens), [['a-phone'], ['b-phone']]);
  assert.equal(visible[0].message.data.type, 'new_order');
  const silent = pushes.filter((push) => push.message.silent);
  assert.deepEqual(silent.map((push) => push.tokens), [['c-phone']]);
  assert.deepEqual(silent[0].message.data, { type: 'orders_changed' });
});

function stockLeft(left) {
  Listing.find.mock.mockImplementation(() => selectable(
    Object.entries(left).map(([listingId, quantityAvailable]) => ({
      _id: listingId, title: `Item ${listingId}`, quantityAvailable, pickupEnd: END, vendor: vendorA,
    }))
  ));
}

test('stock news rides on the new order push; the inbox keeps its own entry', async () => {
  mock.method(Notification, 'find', () => selectable([]));
  stockLeft({ l1: 3 });

  await notifications.orderPlaced([order({ quantity: 3 })]);

  const visible = pushes.filter((push) => !push.message.silent);
  assert.equal(visible.length, 1, 'one buzz for the vendor');
  assert.equal(visible[0].message.title, 'New order received');
  assert.match(visible[0].message.body, /\. Running low: 3 left\.$/);
  assert.equal(saved.filter((note) => note.type === 'stock_low').length, 1);
  assert.equal(saved.some((note) => 'stockNote' in note || 'pushUnlessOn' in note || 'pushNote' in note), false);
});

test('with order alerts off, the stock alert is pushed on its own', async () => {
  mock.method(Notification, 'find', () => selectable([]));
  users[0].notificationPrefs = { orderAlerts: false, stockAlerts: true };
  stockLeft({ l1: 0 });

  await notifications.orderPlaced([order({ quantity: 2 })]);

  const visible = pushes.filter((push) => !push.message.silent);
  assert.deepEqual(visible.map((push) => push.message.title), ['Out of stock: Item l1']);
});

test('with stock alerts off, the new order push has no stock note', async () => {
  mock.method(Notification, 'find', () => selectable([]));
  users[0].notificationPrefs = { orderAlerts: true, stockAlerts: false };
  stockLeft({ l1: 0 });

  await notifications.orderPlaced([order({ quantity: 2 })]);

  const visible = pushes.filter((push) => !push.message.silent);
  assert.equal(visible.length, 1);
  assert.doesNotMatch(visible[0].message.body, /stock/);
});

test('an order that leaves an item running low tells the vendor once per round', async () => {
  stockLeft({ l1: 4 });
  let told = [];
  mock.method(Notification, 'find', (filter) => {
    assert.deepEqual(filter.key.$in, [`stock-low:l1:${END.getTime()}`]);
    return selectable(told);
  });

  await notifications.orderPlaced([order({ quantity: 2 })]);
  const alert = saved.find((note) => note.type === 'stock_low');
  assert.equal(alert.title, 'Running low: Item l1');
  assert.equal(alert.body, 'Only 4 left. Add more stock from your listing if you have extra.');
  assert.equal(alert.listingId, 'l1');
  assert.equal(String(alert.user), String(vendorUserA));

  saved = [];
  told = [{ key: `stock-low:l1:${END.getTime()}` }];
  await notifications.orderPlaced([order({ quantity: 1 })]);
  assert.equal(saved.filter((note) => note.type === 'stock_low').length, 0);
});

test('selling the last one says out of stock; stock still above the limit says nothing', async () => {
  mock.method(Notification, 'find', () => selectable([]));
  stockLeft({ l1: 0 });
  await notifications.orderPlaced([order({ quantity: 2 })]);
  const out = saved.find((note) => note.type === 'stock_low');
  assert.equal(out.title, 'Out of stock: Item l1');
  assert.equal(out.key, `stock-out:l1:${END.getTime()}`);

  saved = [];
  stockLeft({ l1: 8 });
  await notifications.orderPlaced([order({ quantity: 2 })]);
  assert.equal(saved.filter((note) => note.type === 'stock_low').length, 0);

  saved = [];
  stockLeft({ l1: 3 });
  await notifications.orderPlaced([order({ quantity: 1 })]);
  assert.equal(saved.filter((note) => note.type === 'stock_low').length, 0, 'already low before this order');
});

test('the Firebase key works with quotes, \\n or real line breaks', () => {
  const key = '-----BEGIN PRIVATE KEY-----\nABC\n-----END PRIVATE KEY-----\n';
  assert.equal(pushService.privateKey(key), key);
  assert.equal(pushService.privateKey(`"${key.replace(/\n/g, '\\n')}"`), key);
  assert.equal(pushService.privateKey(key.replace(/\n/g, '\\n')), key);
});

test('more than two items are summed up as "and N more"', () => {
  const list = ['A', 'B', 'C', 'D'].map((itemName) => order({ itemName, quantity: 1 }));
  assert.equal(notifications.itemsLabel(list), '1 x A, 1 x B and 2 more');
});

test('orders with different pickup times leave the time out', async () => {
  await notifications.orderPlaced([order(), order({ pickupStart: END, pickupEnd: new Date(END.getTime() + 3600000) })]);
  assert.equal(saved[0].body, '2 x Nasi Lemak and 2 x Nasi Lemak.');
});

test('pickup days are named today and tomorrow in Malaysian time', () => {
  // 23:30 in Malaysia on 19 Nov is 15:30 UTC.
  const lateNight = new Date('2026-11-19T15:30:00Z');
  assert.equal(notifications.dayLabel(new Date('2026-11-19T15:45:00Z'), lateNight), 'today');
  assert.equal(notifications.dayLabel(new Date('2026-11-19T16:30:00Z'), lateNight), 'tomorrow');
  assert.equal(notifications.dayLabel(new Date('2026-11-25T09:00:00Z'), lateNight), '25 Nov');
  assert.equal(notifications.windowLabel(new Date('2026-11-20T03:30:00Z'), new Date('2026-11-20T04:30:00Z')), '11:30 AM–12:30 PM');
});

test('a switched-off type is kept in the inbox but not pushed', async () => {
  users[0].notificationPrefs.orderAlerts = false;

  await notifications.orderPlaced([order()]);

  assert.equal(saved.length, 1);
  assert.equal(pushes.filter((push) => !push.message.silent).length, 0);
});

test('tokens FCM rejects are removed from the account', async () => {
  pushService.sendToTokens.mock.mockImplementation(async (tokens) => tokens);

  await notifications.orderPlaced([order()]);

  assert.deepEqual(pulled[0], [{ _id: vendorUserA }, { $pull: { deviceTokens: { $in: ['a-phone'] } } }]);
});

test('a cancellation tells the vendor who cancelled', async () => {
  await notifications.orderCancelled([order()]);
  assert.equal(saved[0].title, 'Order cancelled by customer');
  assert.equal(saved[0].body, '2 x Nasi Lemak was cancelled and returned to your stock.');

  saved = [];
  await notifications.orderCancelled([order({ quantity: 1 })]);
  assert.equal(saved[0].body, '1 x Nasi Lemak was cancelled and returned to your stock.');

  saved = [];
  await notifications.orderCancelled([order(), order({ itemName: 'Kuih Box', quantity: 1 })]);
  assert.equal(saved[0].title, '2 orders cancelled by customer');
  assert.equal(saved[0].body, '2 x Nasi Lemak and 1 x Kuih Box were cancelled and returned to your stock.');
});

test('item changes name only what customers rely on', () => {
  const before = { title: 'Nasi Lemak', description: 'With egg', isHalal: true, allergens: ['egg'], otherAllergens: [] };
  assert.deepEqual(notifications.changedDetails(before, { ...before, originalPrice: 9 }), []);
  assert.deepEqual(
    notifications.changedDetails(before, { ...before, title: 'Nasi Lemak Ayam', isHalal: false, allergens: ['egg', 'peanut'] }),
    ['name', 'halal status', 'allergens']
  );
  assert.deepEqual(notifications.changedDetails(before, { ...before, description: '' }), ['description']);
});

test('an item change reaches each customer with an active order once', async () => {
  const other = id();
  const firstOrder = id();
  mock.method(Order, 'find', async (filter) => {
    assert.deepEqual(filter.status, { $in: ['pending', 'confirmed'] });
    return [{ _id: firstOrder, customer }, { _id: id(), customer }, { _id: id(), customer: other }];
  });
  const before = { _id: 'l1', title: 'Nasi Lemak', isHalal: true, allergens: [] };

  await notifications.itemChanged(before, { ...before, isHalal: false, allergens: ['egg'] }, { stallName: 'Warung Pak Din' }, NOW);

  assert.equal(saved.length, 2);
  assert.equal(saved[0].orderId, String(firstOrder));
  assert.equal(saved[0].title, 'Your order was updated');
  assert.equal(saved[0].body, 'Warung Pak Din changed the halal status and allergens of Nasi Lemak. Check before pickup.');
});

test('a rename names the old item too', async () => {
  mock.method(Order, 'find', async () => [{ _id: id(), customer }]);
  const before = { _id: 'l1', title: 'Nasi Lemak', isHalal: true, allergens: [] };
  const stall = { stallName: 'Warung Pak Din' };

  await notifications.itemChanged(before, { ...before, title: 'Nasi Goreng' }, stall, NOW);
  assert.equal(saved[0].body, 'Warung Pak Din renamed Nasi Lemak to Nasi Goreng. Check before pickup.');

  saved = [];
  await notifications.itemChanged(before, { ...before, title: 'Nasi Goreng', allergens: ['egg'] }, stall, NOW);
  assert.equal(saved[0].body, 'Warung Pak Din renamed Nasi Lemak to Nasi Goreng and changed its allergens. Check before pickup.');
});

test('an edit that changes nothing customers see sends nothing', async () => {
  mock.method(Order, 'find', async () => assert.fail('no lookup needed'));
  const listing = { _id: 'l1', title: 'Nasi Lemak', allergens: [] };
  assert.deepEqual(await notifications.itemChanged(listing, { ...listing }, {}, NOW), []);
});

const listing = (fields) => ({
  _id: 'l1', title: 'Kuih Box', status: 'active', quantityAvailable: 3, pickupStart: START, pickupEnd: END, ...fields,
});

test('favourite alerts skip anyone told about the item in the last 12 hours', async () => {
  const told = id();
  mock.method(Favourite, 'find', () => selectable([{ customer }, { customer: told }]));
  let recentFilter;
  mock.method(Notification, 'find', (filter) => {
    recentFilter = filter;
    return selectable([{ user: told }]);
  });

  await notifications.favouriteBack(listing(), { stallName: 'Kak Ros' }, 'back_in_stock', NOW);

  assert.equal(saved.length, 1);
  assert.equal(String(saved[0].user), String(customer));
  assert.equal(saved[0].title, 'Kuih Box is back');
  assert.equal(saved[0].body, 'Back in stock at Kak Ros, pickup until 6:00 PM.');
  assert.equal(recentFilter.createdAt.$gt.getTime(), NOW.getTime() - 12 * 60 * 60 * 1000);
});

test('a relist says back on sale', async () => {
  mock.method(Favourite, 'find', () => selectable([{ customer }]));
  mock.method(Notification, 'find', () => selectable([]));
  await notifications.favouriteBack(listing(), { stallName: 'Kak Ros' }, 'relisted', NOW);
  assert.equal(saved[0].body, 'Back on sale at Kak Ros, pickup until 6:00 PM.');
});

test('no favourite alert for a paused, empty or ended listing', async () => {
  mock.method(Favourite, 'find', () => assert.fail('no lookup needed'));
  for (const fields of [{ status: 'paused' }, { quantityAvailable: 0 }, { pickupEnd: NOW }]) {
    assert.deepEqual(await notifications.favouriteBack(listing(fields), {}, 'relisted', NOW), []);
  }
});

test('the opening reminder is added once, dated 30 minutes before pickup', async () => {
  const early = { _id: id(), itemName: 'Nasi Lemak', quantity: 1, stallName: 'Kak Ros', pickupAddress: 'Cafeteria A', pickupStart: START, pickupEnd: END, createdAt: new Date(START.getTime() - 3 * 3600000) };
  const late = { ...early, _id: id(), createdAt: new Date(START.getTime() - 10 * 60000) };
  mock.method(Order, 'find', async () => [early, late]);
  let operations;
  let options;
  mock.method(Notification, 'bulkWrite', async (given, opts) => {
    operations = given;
    options = opts;
  });

  await notifications.addDueReminders(customer, new Date(START.getTime() - 20 * 60000));

  assert.equal(operations.length, 1);
  const { filter, update, upsert } = operations[0].updateOne;
  assert.deepEqual(filter, { user: customer, key: `reminder:${early._id}` });
  assert.equal(upsert, true);
  assert.equal(update.$setOnInsert.title, 'Pickup opens in 30 minutes');
  assert.equal(update.$setOnInsert.body, '1 x Nasi Lemak at Kak Ros, Cafeteria A. 5:00–6:00 PM.');
  assert.equal(update.$setOnInsert.createdAt.getTime(), START.getTime() - 30 * 60000);
  assert.equal(options.timestamps, false);
});

test('the closing reminder comes 30 minutes before pickup ends, also for orders placed during pickup', async () => {
  const during = { _id: id(), itemName: 'Nasi Lemak', quantity: 2, stallName: 'Kak Ros', pickupStart: START, pickupEnd: END, createdAt: new Date(START.getTime() + 5 * 60000) };
  mock.method(Order, 'find', async () => [during]);
  let operations;
  mock.method(Notification, 'bulkWrite', async (given) => { operations = given; });

  await notifications.addDueReminders(customer, new Date(END.getTime() - 20 * 60000));

  assert.equal(operations.length, 1);
  const { filter, update } = operations[0].updateOne;
  assert.deepEqual(filter, { user: customer, key: `reminder-end:${during._id}` });
  assert.equal(update.$setOnInsert.title, 'Pickup ends in 30 minutes');
  assert.equal(update.$setOnInsert.body, "Don't forget to collect 2 x Nasi Lemak at Kak Ros before 6:00 PM.");
  assert.equal(update.$setOnInsert.createdAt.getTime(), END.getTime() - 30 * 60000);
});

test('no closing reminder when pickup lasts 30 minutes or less', async () => {
  const short = { _id: id(), itemName: 'Teh', quantity: 1, stallName: 'Kak Ros', pickupStart: START, pickupEnd: new Date(START.getTime() + 30 * 60000), createdAt: NOW };
  mock.method(Order, 'find', async () => [short]);
  let operations = [];
  mock.method(Notification, 'bulkWrite', async (given) => { operations = given; });

  await notifications.addDueReminders(customer, new Date(START.getTime() + 10 * 60000));

  assert.deepEqual(operations.map((item) => item.updateOne.filter.key), [`reminder:${short._id}`]);
});

test('two requests adding the same reminder at once is not an error', async () => {
  mock.method(Order, 'find', async () => [{ _id: id(), pickupStart: START, pickupEnd: END, createdAt: NOW }]);
  mock.method(Notification, 'bulkWrite', async () => {
    const err = new Error('dup');
    err.code = 11000;
    throw err;
  });
  await notifications.addDueReminders(customer, new Date(START.getTime() - 60000));
});

test('nothing runs in the background without a database connection', async () => {
  let ran = false;
  notifications.inBackground(() => { ran = true; });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(ran, false);
});

test('without Firebase settings nothing is sent and no token is dropped', async () => {
  mock.restoreAll();
  const keys = ['FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY'];
  const kept = keys.map((key) => process.env[key]);
  keys.forEach((key) => delete process.env[key]);
  mock.method(console, 'log', () => {});
  try {
    assert.equal(pushService.isConfigured(), false);
    assert.deepEqual(await pushService.sendToTokens(['a'], { title: 't', body: 'b' }), []);
  } finally {
    keys.forEach((key, index) => { if (kept[index] !== undefined) process.env[key] = kept[index]; });
  }
});

test('visible pushes use the order or reminder channel; silent ones carry data only', () => {
  const visible = pushService.messageFor({ title: 'T', body: 'B', channel: 'reminders', data: { orderId: 7, listingId: undefined } });
  assert.deepEqual(visible.notification, { title: 'T', body: 'B' });
  assert.equal(visible.android.notification.channelId, 'reminders');
  assert.deepEqual(visible.data, { orderId: '7' });
  const silent = pushService.messageFor({ silent: true, data: { type: 'orders_changed' } });
  assert.equal(silent.notification, undefined);
  assert.deepEqual(silent.data, { type: 'orders_changed' });
});

// Wiring: the request handlers hand the right orders to the alerts.
function signedInAs(user) {
  mock.method(User, 'findById', () => query(user));
  return signToken(user.id);
}

function captureBackground() {
  const tasks = [];
  mock.method(notifications, 'inBackground', (task) => tasks.push(task));
  return tasks;
}

test('Order Now alerts the vendor, but a repeated request does not', async () => {
  const tasks = captureBackground();
  const placed = order();
  mock.method(notifications, 'orderPlaced', async () => {});
  const token = signedInAs(new User({ name: 'C', email: 'c@example.com', role: 'customer', emailVerified: true }));
  const body = { listingId: String(id()), quantity: 1, requestId: 'req-12345678' };

  mock.method(orderService, 'placeOrder', async () => ({ order: placed }));
  await call('/api/orders', { method: 'POST', token, body });
  orderService.placeOrder.mock.mockImplementation(async () => ({ order: placed, repeated: true }));
  await call('/api/orders', { method: 'POST', token, body });

  assert.equal(tasks.length, 1);
  await tasks[0]();
  assert.deepEqual(notifications.orderPlaced.mock.calls[0].arguments, [[placed]]);
});

test('turning stock back on from zero alerts favourites; other changes do not', async () => {
  const tasks = captureBackground();
  const vendor = { _id: id(), stallName: 'Kak Ros' };
  const token = signedInAs(new User({ name: 'V', email: 'v@example.com', role: 'vendor', emailVerified: true }));
  const listingId = String(id());
  mock.method(Vendor, 'findOne', async () => vendor);
  let stock = 0;
  mock.method(Listing, 'findOne', async () => ({ _id: listingId, quantityAvailable: stock }));
  mock.method(Listing, 'findOneAndUpdate', async () => ({ _id: listingId, quantityAvailable: 5, status: 'active' }));
  mock.method(notifications, 'favouriteBack', async () => {});

  await call(`/api/listings/${listingId}/stock`, { method: 'PATCH', token, body: { quantity: 5, expectedQuantity: 0 } });
  stock = 2;
  await call(`/api/listings/${listingId}/stock`, { method: 'PATCH', token, body: { quantity: 5, expectedQuantity: 2 } });

  assert.equal(tasks.length, 1);
  await tasks[0]();
  const [, givenVendor, kind] = notifications.favouriteBack.mock.calls[0].arguments;
  assert.equal(givenVendor, vendor);
  assert.equal(kind, 'back_in_stock');
});
