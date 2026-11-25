const mongoose = require('mongoose');
const Notification = require('../models/Notification');
const User = require('../models/User');
const Vendor = require('../models/Vendor');
const Order = require('../models/Order');
const Favourite = require('../models/Favourite');
const Listing = require('../models/Listing');
const { LOW_STOCK_LIMIT } = require('../models/listingOptions');
const pushService = require('./pushService');

const TIME_ZONE = 'Asia/Kuala_Lumpur';
// The phone reminds this long before pickup opens, and again before it ends.
const REMINDER_LEAD_MS = 30 * 60 * 1000;
// A customer hears about the same favourite at most once in this time.
const FAVOURITE_GAP_MS = 12 * 60 * 60 * 1000;
const OPEN_STATUSES = ['pending', 'confirmed'];
const SUMMARY_ITEMS = 2;

// The My Profile switch that controls each type's push.
const PREF_FOR = {
  new_order: 'orderAlerts',
  order_cancelled: 'orderAlerts',
  item_changed: 'itemChanges',
  pickup_reminder: 'pickupReminders',
  favourite_back: 'favourites',
  stock_low: 'stockAlerts',
};
const PREFS_BY_ROLE = {
  vendor: ['orderAlerts', 'stockAlerts'],
  customer: ['itemChanges', 'pickupReminders', 'favourites'],
};

function isReady() {
  return mongoose.connection.readyState === 1;
}

function timeLabel(date) {
  return new Date(date).toLocaleTimeString('en-US', { timeZone: TIME_ZONE, hour: 'numeric', minute: '2-digit' });
}

// "5:00–6:00 PM", or "11:30 AM–12:30 PM" when the halves of the day differ.
function windowLabel(start, end) {
  const from = timeLabel(start);
  const to = timeLabel(end);
  const [fromTime, fromHalf] = from.split(' ');
  return fromHalf === to.split(' ')[1] ? `${fromTime}–${to}` : `${from}–${to}`;
}

function dayKey(date) {
  return new Date(date).toLocaleDateString('en-CA', { timeZone: TIME_ZONE });
}

function dayLabel(date, now = new Date()) {
  const day = dayKey(date);
  if (day === dayKey(now)) return 'today';
  if (day === dayKey(new Date(now.getTime() + 24 * 60 * 60 * 1000))) return 'tomorrow';
  return new Date(date).toLocaleDateString('en-GB', { timeZone: TIME_ZONE, day: 'numeric', month: 'short' });
}

const sameTime = (a, b) => new Date(a).getTime() === new Date(b).getTime();

function groupBy(items, keyOf) {
  const groups = new Map();
  for (const item of items) {
    const key = keyOf(item);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(item);
  }
  return groups;
}

// "2 x Nasi Lemak, 1 x Kuih Box and 2 more"
function itemsLabel(orders) {
  const names = orders.slice(0, SUMMARY_ITEMS).map((order) => `${order.quantity} x ${order.itemName}`);
  const rest = orders.length - names.length;
  return rest > 0 ? `${names.join(', ')} and ${rest} more` : names.join(' and ');
}

// ", pickup today 5:00–6:00 PM" when every order shares one window.
function pickupLabel(orders, now = new Date()) {
  const [first] = orders;
  const shared = orders.every(
    (order) => sameTime(order.pickupStart, first.pickupStart) && sameTime(order.pickupEnd, first.pickupEnd)
  );
  return shared ? `, pickup ${dayLabel(first.pickupStart, now)} ${windowLabel(first.pickupStart, first.pickupEnd)}` : '';
}

// A tap opens the listing when every order is for the same one.
function onlyListing(orders) {
  const ids = new Set(orders.map((order) => String(order.listing)));
  return ids.size === 1 ? [...ids][0] : undefined;
}

function placeLabel(order) {
  return order.pickupAddress ? `${order.stallName}, ${order.pickupAddress}` : order.stallName;
}

// The two pickup reminders: before pickup opens, and before it ends.
const REMINDERS = {
  opens: {
    key: 'reminder',
    title: 'Pickup opens in 30 minutes',
    at: (order) => new Date(order.pickupStart).getTime() - REMINDER_LEAD_MS,
    body: (order) => `${order.quantity} x ${order.itemName} at ${placeLabel(order)}. ${windowLabel(order.pickupStart, order.pickupEnd)}.`,
  },
  ends: {
    key: 'reminder-end',
    title: 'Pickup ends in 30 minutes',
    at: (order) => new Date(order.pickupEnd).getTime() - REMINDER_LEAD_MS,
    body: (order) => `Don't forget to collect ${order.quantity} x ${order.itemName} at ${order.stallName} before ${timeLabel(order.pickupEnd)}.`,
  },
};

// A reminder is due once its time has passed, if the order was placed before it.
// The closing one only when pickup lasts longer than 30 minutes.
function dueReminders(order, now = new Date()) {
  const placed = new Date(order.createdAt).getTime();
  return Object.values(REMINDERS).filter((reminder) => {
    const at = reminder.at(order);
    if (reminder === REMINDERS.ends && at <= new Date(order.pickupStart).getTime()) return false;
    return at <= now.getTime() && placed <= at;
  });
}

// Saves each notification to its user's inbox, then pushes it unless that type is switched off.
// Push-only extras on an entry, never saved: `stockNote` is added to a new
// order's push when the vendor wants stock alerts, and `pushUnlessOn` skips
// the push when that switch is on (its news already went with another push).
function pushPlan(entry, prefs) {
  if (entry.pushUnlessOn && prefs?.[entry.pushUnlessOn] !== false) return null;
  const note = entry.stockNote && prefs?.stockAlerts !== false ? ` ${entry.stockNote}` : '';
  return { body: `${entry.body}${note}` };
}

async function deliver(entries) {
  if (!entries.length) return [];
  const plans = entries.map(({ stockNote, pushUnlessOn }) => ({ stockNote, pushUnlessOn }));
  const docs = entries.map(({ stockNote, pushUnlessOn, ...doc }) => doc);
  const saved = await Notification.insertMany(docs, { ordered: false });
  const userIds = [...new Set(saved.map((note) => String(note.user)))];
  const users = await User.find({ _id: { $in: userIds } }).select('+deviceTokens notificationPrefs');
  const byId = new Map(users.map((user) => [String(user._id), user]));

  for (const [index, note] of saved.entries()) {
    const user = byId.get(String(note.user));
    if (!user?.deviceTokens?.length) continue;
    if (user.notificationPrefs?.[PREF_FOR[note.type]] === false) continue;
    const plan = pushPlan({ ...plans[index], body: note.body }, user.notificationPrefs);
    if (!plan) continue;
    const dead = await pushService.sendToTokens(user.deviceTokens, {
      title: note.title,
      body: plan.body,
      channel: note.type === 'pickup_reminder' ? 'reminders' : 'orders',
      data: { type: note.type, notificationId: note._id, orderId: note.orderId, listingId: note.listingId },
    });
    if (dead.length) await User.updateOne({ _id: user._id }, { $pull: { deviceTokens: { $in: dead } } });
  }
  return saved;
}

// A silent push that tells the customer's phones to reschedule their pickup reminders.
async function resync(customerIds) {
  const ids = [...new Set(customerIds.map(String))];
  if (!ids.length) return;
  const users = await User.find({ _id: { $in: ids } }).select('+deviceTokens');
  for (const user of users) {
    if (!user.deviceTokens?.length) continue;
    const dead = await pushService.sendToTokens(user.deviceTokens, { silent: true, data: { type: 'orders_changed' } });
    if (dead.length) await User.updateOne({ _id: user._id }, { $pull: { deviceTokens: { $in: dead } } });
  }
}

async function vendorUsers(vendorIds) {
  const vendors = await Vendor.find({ _id: { $in: vendorIds } }).select('user');
  return new Map(vendors.map((vendor) => [String(vendor._id), vendor.user]));
}

// One alert per vendor for the orders a checkout (or Order Now) placed.
async function orderPlaced(orders) {
  if (!orders.length) return [];
  const groups = groupBy(orders, (order) => String(order.vendor));
  const users = await vendorUsers([...groups.keys()]);
  // Stock news rides on the new order's push, so the vendor's phone buzzes once.
  // The inbox still gets its own stock entry.
  const stock = await stockRunningLow(orders, users);
  const entries = [];
  for (const [vendorId, list] of groups) {
    const user = users.get(vendorId);
    if (!user) continue;
    const notes = stock.filter((entry) => String(entry.user) === String(user)).map((entry) => entry.pushNote);
    entries.push({
      user,
      type: 'new_order',
      title: list.length === 1 ? 'New order received' : `${list.length} new orders received`,
      body: `${itemsLabel(list)}${pickupLabel(list)}.`,
      listingId: onlyListing(list),
      stockNote: notes.length ? notes.join(' ') : undefined,
    });
  }
  const saved = await deliver([
    ...entries,
    ...stock.map(({ pushNote, ...entry }) => ({ ...entry, pushUnlessOn: 'orderAlerts' })),
  ]);
  await resync(orders.map((order) => order.customer));
  return saved;
}

// The stock alerts these orders cause: once per pickup round when an item runs
// low, and again when it runs out.
async function stockRunningLow(orders, vendorUserIds) {
  const sold = new Map();
  for (const order of orders) {
    const key = String(order.listing);
    sold.set(key, (sold.get(key) ?? 0) + order.quantity);
  }
  const listings = await Listing.find({ _id: { $in: [...sold.keys()] } }).select('title quantityAvailable pickupEnd vendor');
  const entries = [];
  for (const listing of listings) {
    const left = listing.quantityAvailable;
    const before = left + sold.get(String(listing._id));
    const user = vendorUserIds.get(String(listing.vendor));
    if (!user || left > LOW_STOCK_LIMIT || before <= (left === 0 ? 0 : LOW_STOCK_LIMIT)) continue;
    const level = left === 0 ? 'out' : 'low';
    entries.push({
      user,
      type: 'stock_low',
      title: level === 'out' ? `Out of stock: ${listing.title}` : `Running low: ${listing.title}`,
      body: level === 'out'
        ? 'Nothing is left to order. Add more stock from your listing if you have extra.'
        : `Only ${left} left. Add more stock from your listing if you have extra.`,
      listingId: String(listing._id),
      key: `stock-${level}:${listing._id}:${new Date(listing.pickupEnd).getTime()}`,
      pushNote: level === 'out' ? `Now out of stock: ${listing.title}.` : `Running low: ${left} left.`,
    });
  }
  if (!entries.length) return [];
  const told = await Notification.find({ key: { $in: entries.map((entry) => entry.key) } }).select('key');
  const toldKeys = new Set(told.map((note) => note.key));
  return entries.filter((entry) => !toldKeys.has(entry.key));
}

function cancelledBody(orders) {
  return `${itemsLabel(orders)} ${orders.length > 1 ? 'were' : 'was'} cancelled and returned to your stock.`;
}

async function orderCancelled(orders) {
  if (!orders.length) return [];
  const groups = groupBy(orders, (order) => String(order.vendor));
  const users = await vendorUsers([...groups.keys()]);
  const entries = [];
  for (const [vendorId, list] of groups) {
    const user = users.get(vendorId);
    if (!user) continue;
    entries.push({
      user,
      type: 'order_cancelled',
      title: list.length === 1 ? 'Order cancelled by customer' : `${list.length} orders cancelled by customer`,
      body: cancelledBody(list),
      listingId: onlyListing(list),
    });
  }
  const saved = await deliver(entries);
  await resync(orders.map((order) => order.customer));
  return saved;
}

const textOf = (value) => (value ?? '').trim();
const listOf = (values) => [...(values ?? [])].map(String).sort().join('|');

// The details customers rely on when they collect, in the order they're named.
function changedDetails(before, after) {
  const changed = [];
  if (textOf(before.title) !== textOf(after.title)) changed.push('name');
  if (textOf(before.description) !== textOf(after.description)) changed.push('description');
  if (Boolean(before.isHalal) !== Boolean(after.isHalal)) changed.push('halal status');
  if (listOf(before.allergens) !== listOf(after.allergens)
    || listOf(before.otherAllergens) !== listOf(after.otherAllergens)) changed.push('allergens');
  return changed;
}

function joinWords(words) {
  if (words.length < 2) return words.join('');
  return `${words.slice(0, -1).join(', ')} and ${words.at(-1)}`;
}

// A new name is told with the old one, so customers still know which item it is.
function itemChangedBody(before, after, vendor, changed) {
  const others = changed.filter((detail) => detail !== 'name');
  if (others.length === changed.length) {
    return `${vendor.stallName} changed the ${joinWords(changed)} of ${textOf(after.title)}. Check before pickup.`;
  }
  const also = others.length ? ` and changed its ${joinWords(others)}` : '';
  return `${vendor.stallName} renamed ${textOf(before.title)} to ${textOf(after.title)}${also}. Check before pickup.`;
}

// Tells customers with active orders for the item what changed.
async function itemChanged(before, after, vendor, now = new Date()) {
  const changed = changedDetails(before, after);
  if (!changed.length) return [];
  const orders = await Order.find(
    { listing: after._id, status: { $in: OPEN_STATUSES }, pickupEnd: { $gt: now } },
    'customer',
    { sort: { createdAt: 1 } }
  );
  const firstByCustomer = new Map();
  for (const order of orders) {
    const key = String(order.customer);
    if (!firstByCustomer.has(key)) firstByCustomer.set(key, order);
  }
  const body = itemChangedBody(before, after, vendor, changed);
  const entries = [...firstByCustomer.values()].map((order) => ({
    user: order.customer,
    type: 'item_changed',
    title: 'Your order was updated',
    body,
    orderId: String(order._id),
  }));
  return deliver(entries);
}

// Tells customers who saved the item that it's back on sale or back in stock.
async function favouriteBack(listing, vendor, kind, now = new Date()) {
  if (listing.status !== 'active' || listing.quantityAvailable <= 0 || listing.pickupEnd <= now) return [];
  const favourites = await Favourite.find({ listing: listing._id }).select('customer');
  if (!favourites.length) return [];
  const customers = favourites.map((favourite) => favourite.customer);
  const recent = await Notification.find({
    type: 'favourite_back',
    listingId: String(listing._id),
    user: { $in: customers },
    createdAt: { $gt: new Date(now.getTime() - FAVOURITE_GAP_MS) },
  }).select('user');
  const told = new Set(recent.map((note) => String(note.user)));
  const entries = customers
    .filter((customer) => !told.has(String(customer)))
    .map((customer) => ({
      user: customer,
      type: 'favourite_back',
      title: `${listing.title} is back`,
      body: `Back ${kind === 'relisted' ? 'on sale' : 'in stock'} at ${vendor.stallName}, pickup until ${timeLabel(listing.pickupEnd)}.`,
      listingId: String(listing._id),
    }));
  return deliver(entries);
}

// The phone shows pickup reminders itself; this adds the ones now due to the inbox.
async function addDueReminders(customer, now = new Date()) {
  const orders = await Order.find(
    {
      customer,
      status: { $in: OPEN_STATUSES },
      pickupEnd: { $gt: now },
      pickupStart: { $lte: new Date(now.getTime() + REMINDER_LEAD_MS) },
    },
    'itemName quantity stallName pickupAddress pickupStart pickupEnd createdAt'
  );
  const operations = [];
  for (const order of orders) {
    for (const reminder of dueReminders(order, now)) {
      const key = `${reminder.key}:${order._id}`;
      operations.push({
        updateOne: {
          filter: { user: customer, key },
          update: {
            $setOnInsert: {
              user: customer,
              key,
              type: 'pickup_reminder',
              title: reminder.title,
              body: reminder.body(order),
              orderId: String(order._id),
              createdAt: new Date(reminder.at(order)),
            },
          },
          upsert: true,
        },
      });
    }
  }
  if (!operations.length) return;
  try {
    await Notification.bulkWrite(operations, { ordered: false, timestamps: false });
  } catch (err) {
    // Two requests at once can race to add the same reminder; one wins.
    if (err?.code !== 11000 && !err?.writeErrors?.every((item) => item.code === 11000)) throw err;
  }
}

// Runs a notification task after the reply, so a failed push never fails the request.
function inBackground(task) {
  if (!module.exports.isReady()) return;
  setImmediate(() => {
    Promise.resolve()
      .then(task)
      .catch((err) => console.error('Sending a notification failed:', err.message));
  });
}

module.exports = {
  isReady,
  inBackground,
  deliver,
  resync,
  orderPlaced,
  orderCancelled,
  stockRunningLow,
  itemChanged,
  favouriteBack,
  addDueReminders,
  changedDetails,
  itemsLabel,
  windowLabel,
  timeLabel,
  dayLabel,
  REMINDERS,
  PREF_FOR,
  PREFS_BY_ROLE,
  REMINDER_LEAD_MS,
  FAVOURITE_GAP_MS,
};
