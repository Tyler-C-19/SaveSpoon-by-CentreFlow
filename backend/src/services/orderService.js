const mongoose = require('mongoose');
const Listing = require('../models/Listing');
const Vendor = require('../models/Vendor');
const Order = require('../models/Order');

const LISTING_GONE = 'LISTING_GONE';
const SOLD_OUT = 'SOLD_OUT';
const PICKUP_ENDED = 'PICKUP_ENDED';
const NOT_ENOUGH_STOCK = 'NOT_ENOUGH_STOCK';

const GONE = { status: 404, code: LISTING_GONE, error: 'This item is no longer available.' };

const soldOut = (title) => ({
  status: 409,
  code: SOLD_OUT,
  error: `Sorry, ${title} has just sold out.`,
});

const pickupEnded = (title) => ({
  status: 409,
  code: PICKUP_ENDED,
  error: `Pickup for ${title} has ended.`,
});

const notEnoughStock = (title, available) => ({
  status: 409,
  code: NOT_ENOUGH_STOCK,
  available,
  error: `Only ${available} ${title} left. Choose ${available} or fewer and try again.`,
});

const roundMoney = (value) => Math.round(value * 100) / 100;

const isDuplicateKey = (err) => err?.code === 11000;

function unavailableProblem(listing, now = new Date()) {
  if (!listing || !['active', 'sold_out'].includes(listing.status)) return GONE;
  if (listing.pickupEnd <= now) return pickupEnded(listing.title);
  if (listing.status === 'sold_out' || listing.quantityAvailable <= 0) return soldOut(listing.title);
  return null;
}

function reservationProblem(listing, now = new Date()) {
  return unavailableProblem(listing, now)
    || notEnoughStock(listing.title, listing.quantityAvailable);
}

async function findLiveListing(listingId) {
  if (!mongoose.isValidObjectId(listingId)) return {};
  const listing = await Listing.findById(listingId);
  if (!listing) return {};
  const vendor = await Vendor.findById(listing.vendor);
  return vendor ? { listing, vendor } : {};
}

// Stock and the sales count change in one atomic update, so concurrent orders can't oversell.
function reserveStock(listingId, quantity, now = new Date()) {
  return Listing.findOneAndUpdate(
    {
      _id: listingId,
      status: 'active',
      quantityAvailable: { $gte: quantity },
      pickupEnd: { $gt: now },
    },
    { $inc: { quantityAvailable: -quantity, soldCount: quantity } },
    { returnDocument: 'after' }
  );
}

function releaseStock(listingId, quantity) {
  return Listing.updateOne(
    { _id: listingId },
    { $inc: { quantityAvailable: quantity, soldCount: -quantity } }
  );
}

function orderFields({ customer, listing, vendor, quantity, requestId, checkoutId }) {
  return {
    customer,
    vendor: vendor._id,
    listing: listing._id,
    requestId,
    checkoutId,
    itemName: listing.title,
    category: listing.category,
    imageThumbUrl: listing.imageThumbUrl ?? undefined,
    stallName: vendor.stallName,
    pickupAddress: vendor.address,
    pickupStart: listing.pickupStart,
    pickupEnd: listing.pickupEnd,
    quantity,
    unitPrice: listing.discountedPrice,
    originalUnitPrice: listing.originalPrice,
    totalPrice: roundMoney(listing.discountedPrice * quantity),
  };
}

async function placeOrder({ customer, listingId, quantity, requestId }) {
  const earlier = await Order.findOne({ customer, requestId });
  if (earlier) return { order: earlier, repeated: true };

  const { listing, vendor } = await findLiveListing(listingId);
  if (!listing) return { problem: GONE };

  const reserved = await reserveStock(listing._id, quantity);
  if (!reserved) {
    return { problem: reservationProblem(await Listing.findById(listing._id)) };
  }

  try {
    const order = await Order.create(
      orderFields({ customer, listing, vendor, quantity, requestId })
    );
    return { order };
  } catch (err) {
    await releaseStock(listing._id, quantity);
    if (!isDuplicateKey(err)) throw err;
    return { order: await Order.findOne({ customer, requestId }), repeated: true };
  }
}

const ORDER_TABS = ['all', 'upcoming', 'history', 'cancelled'];
const OPEN_STATUSES = ['pending', 'confirmed'];
const ORDER_AGAIN_SIZE = 6;
// How many past items are checked for Order Again before giving up.
const ORDER_AGAIN_LOOKBACK = 50;

const ORDER_FIELDS = 'itemName category stallName pickupAddress pickupStart pickupEnd quantity unitPrice originalUnitPrice totalPrice status checkoutId createdAt cancelledAt cancelledBy cancelReason';
const CARD_FIELDS = 'title description category isHalal originalPrice discountedPrice quantityAvailable soldCount pickupStart pickupEnd allergens otherAllergens imageUrl status createdAt vendor';

// Upcoming: still to collect. History: finished, cancelled, or the pickup window has passed.
function orderTabQuery(tab, customer, now = new Date()) {
  if (tab === 'upcoming') {
    return {
      filter: { customer, status: { $in: OPEN_STATUSES }, pickupEnd: { $gt: now } },
      sort: { pickupStart: 1, pickupEnd: 1, _id: 1 },
    };
  }
  if (tab === 'cancelled') {
    return { filter: { customer, status: 'cancelled' }, sort: { createdAt: -1, _id: -1 } };
  }
  if (tab === 'history') {
    return {
      filter: {
        customer,
        $or: [{ status: { $nin: OPEN_STATUSES } }, { pickupEnd: { $lte: now } }],
      },
      sort: { createdAt: -1, _id: -1 },
    };
  }
  return { filter: { customer }, sort: { createdAt: -1, _id: -1 } };
}

async function listOrders({ customer, tab, page, pageSize }) {
  const { filter, sort } = orderTabQuery(tab, customer);
  const found = await Order.find(filter, ORDER_FIELDS, {
    sort,
    skip: (page - 1) * pageSize,
    limit: pageSize + 1,
    lean: true,
  });
  return { orders: found.slice(0, pageSize), hasMore: found.length > pageSize };
}

function findOwnOrder(customer, orderId) {
  if (!mongoose.isValidObjectId(orderId)) return null;
  return Order.findOne({ _id: orderId, customer }, ORDER_FIELDS, { lean: true });
}

// Listings the customer ordered before that can be ordered now, most recently ordered first.
async function orderAgainListings(customer, now = new Date()) {
  const ordered = await Order.aggregate([
    { $match: { customer } },
    { $group: { _id: '$listing', lastOrdered: { $max: '$createdAt' } } },
    { $sort: { lastOrdered: -1, _id: 1 } },
    { $limit: ORDER_AGAIN_LOOKBACK },
  ]);
  if (ordered.length === 0) return [];

  const ids = ordered.map((item) => String(item._id));
  const listings = await Listing.find(
    {
      _id: { $in: ids },
      status: 'active',
      quantityAvailable: { $gt: 0 },
      pickupEnd: { $gt: now },
    },
    CARD_FIELDS,
    { lean: true }
  );
  const vendors = await Vendor.find(
    { _id: { $in: listings.map((listing) => listing.vendor) } },
    'stallName',
    { lean: true }
  );
  const stallNames = new Map(vendors.map((vendor) => [String(vendor._id), vendor.stallName]));

  return listings
    .filter((listing) => stallNames.has(String(listing.vendor)))
    .sort((a, b) => ids.indexOf(String(a._id)) - ids.indexOf(String(b._id)))
    .slice(0, ORDER_AGAIN_SIZE)
    .map(({ vendor, ...listing }) => ({ ...listing, stallName: stallNames.get(String(vendor)) }));
}

const CANCEL_GRACE_MS = 5 * 60 * 1000;
const CANCEL_LIMIT = 5;
const CANCEL_LIMIT_WINDOW_MS = 24 * 60 * 60 * 1000;
const CANCEL_LIMIT_CODE = 'CANCEL_LIMIT';

const ORDER_NOT_FOUND_PROBLEM = { status: 404, error: "We couldn't find this order." };

// Open orders can be cancelled before pickup starts, or within a few minutes of ordering,
// but never once pickup has ended.
function cancellableFilter(now = new Date()) {
  return {
    status: { $in: OPEN_STATUSES },
    pickupEnd: { $gt: now },
    $or: [
      { pickupStart: { $gt: now } },
      { createdAt: { $gt: new Date(now.getTime() - CANCEL_GRACE_MS) } },
    ],
  };
}

function cancelUntil(order, now = new Date()) {
  if (!OPEN_STATUSES.includes(order.status)) return null;
  const start = order.pickupStart && new Date(order.pickupStart).getTime();
  const end = order.pickupEnd && new Date(order.pickupEnd).getTime();
  const placed = order.createdAt && new Date(order.createdAt).getTime();
  if (!start || !end) return null;
  const until = Math.min(Math.max(start, placed ? placed + CANCEL_GRACE_MS : 0), end);
  return until > now.getTime() ? new Date(until) : null;
}

// A newly placed order with its cancel deadline, for the Order Placed page.
function withCancelUntil(order, now = new Date()) {
  if (!order) return order;
  const plain = order.toObject ? order.toObject() : order;
  return { ...plain, cancelUntil: cancelUntil(plain, now) };
}

function cancelClosedProblem(order, now = new Date()) {
  if (order.status === 'cancelled') {
    return { status: 409, code: 'ALREADY_CANCELLED', error: 'This order is already cancelled.' };
  }
  if (order.status === 'completed') {
    return { status: 409, code: 'ORDER_COMPLETED', error: 'This order has already been collected.' };
  }
  if (new Date(order.pickupEnd) <= now) {
    return { status: 409, code: PICKUP_ENDED, error: 'Pickup for this order has ended.' };
  }
  return {
    status: 409,
    code: 'PICKUP_STARTED',
    error: 'Pickup has started, so this order can no longer be cancelled.',
  };
}

function waitLabel(ms) {
  const minutes = Math.max(1, Math.ceil(ms / 60000));
  if (minutes < 60) return minutes === 1 ? '1 minute' : `${minutes} minutes`;
  const hours = Math.ceil(minutes / 60);
  return hours === 1 ? '1 hour' : `${hours} hours`;
}

// Orders cancelled together share one cancelledAt, so a whole checkout counts once.
async function cancelLimitProblem(customer, now = new Date()) {
  const since = new Date(now.getTime() - CANCEL_LIMIT_WINDOW_MS);
  const recent = await Order.aggregate([
    { $match: { customer, cancelledBy: 'customer', cancelledAt: { $gt: since } } },
    { $group: { _id: '$cancelledAt' } },
    { $sort: { _id: -1 } },
    { $limit: CANCEL_LIMIT },
  ]);
  if (recent.length < CANCEL_LIMIT) return null;
  const freeAt = new Date(recent[CANCEL_LIMIT - 1]._id).getTime() + CANCEL_LIMIT_WINDOW_MS;
  return {
    status: 429,
    code: CANCEL_LIMIT_CODE,
    error: `You can cancel up to ${CANCEL_LIMIT} times in 24 hours. Try again in about ${waitLabel(freeAt - now.getTime())}.`,
  };
}

// Stock goes back only to the round the order came from, so a later round is never changed.
function returnStock(order) {
  return Listing.updateOne(
    { _id: order.listing, pickupEnd: order.pickupEnd, soldCount: { $gte: order.quantity } },
    { $inc: { quantityAvailable: order.quantity, soldCount: -order.quantity } }
  );
}

async function cancelOne({ customer, orderId, reason, now }) {
  const changes = { status: 'cancelled', cancelledAt: now, cancelledBy: 'customer' };
  if (reason) changes.cancelReason = reason;
  // Matching only cancellable orders means a repeated request can't return stock twice.
  const cancelled = await Order.findOneAndUpdate(
    { _id: orderId, customer, ...cancellableFilter(now) },
    { $set: changes },
    { returnDocument: 'after' }
  );
  if (cancelled) await returnStock(cancelled);
  return cancelled;
}

function publicOrder(order) {
  const { customer, vendor, listing, requestId, ...rest } = order.toObject ? order.toObject() : order;
  return rest;
}

async function cancelOrder({ customer, orderId, reason, wholeCheckout = false, now = new Date() }) {
  if (!mongoose.isValidObjectId(orderId)) return { problem: ORDER_NOT_FOUND_PROBLEM };
  const order = await Order.findOne({ _id: orderId, customer });
  if (!order) return { problem: ORDER_NOT_FOUND_PROBLEM };
  if (!cancelUntil(order, now)) return { problem: cancelClosedProblem(order, now) };

  const limited = await cancelLimitProblem(customer, now);
  if (limited) return { problem: limited };

  const first = await cancelOne({ customer, orderId: order._id, reason, now });
  if (!first) {
    const latest = (await Order.findOne({ _id: order._id, customer })) ?? order;
    return { problem: cancelClosedProblem(latest, now) };
  }

  const cancelled = [first];
  const skipped = [];
  if (wholeCheckout && order.checkoutId) {
    const others = await Order.find({
      customer,
      checkoutId: order.checkoutId,
      _id: { $ne: order._id },
      status: { $in: OPEN_STATUSES },
      pickupEnd: { $gt: now },
    });
    for (const other of others) {
      const done = await cancelOne({ customer, orderId: other._id, reason, now });
      if (done) cancelled.push(done);
      else skipped.push(other);
    }
  }
  return { cancelled: cancelled.map(publicOrder), skipped: skipped.map(publicOrder) };
}

const CHECKOUT_ITEM_FIELDS = 'itemName quantity stallName status createdAt pickupStart pickupEnd';

// Adds when the order can be cancelled until, and the other open orders from its checkout.
async function withCancelInfo(order, customer, now = new Date()) {
  const until = cancelUntil(order, now);
  let checkoutOrders = [];
  if (until && order.checkoutId) {
    const others = await Order.find(
      {
        customer,
        checkoutId: order.checkoutId,
        _id: { $ne: order._id },
        status: { $in: OPEN_STATUSES },
        pickupEnd: { $gt: now },
      },
      CHECKOUT_ITEM_FIELDS,
      { sort: { createdAt: 1, _id: 1 }, lean: true }
    );
    checkoutOrders = others.map((other) => ({
      _id: other._id,
      itemName: other.itemName,
      quantity: other.quantity,
      stallName: other.stallName,
      canCancel: Boolean(cancelUntil(other, now)),
    }));
  }
  return {
    ...order,
    cancelUntil: until,
    checkoutOrders,
    otherCancellable: checkoutOrders.filter((other) => other.canCancel).length,
  };
}

module.exports = {
  CANCEL_GRACE_MS,
  CANCEL_LIMIT,
  CANCEL_LIMIT_CODE,
  cancellableFilter,
  cancelUntil,
  withCancelUntil,
  cancelOrder,
  withCancelInfo,
  ORDER_TABS,
  ORDER_AGAIN_SIZE,
  orderTabQuery,
  listOrders,
  findOwnOrder,
  orderAgainListings,
  GONE,
  LISTING_GONE,
  SOLD_OUT,
  PICKUP_ENDED,
  NOT_ENOUGH_STOCK,
  unavailableProblem,
  reservationProblem,
  findLiveListing,
  reserveStock,
  releaseStock,
  orderFields,
  placeOrder,
  isDuplicateKey,
  roundMoney,
};
