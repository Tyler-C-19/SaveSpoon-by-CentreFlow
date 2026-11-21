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

const ORDER_TABS = ['all', 'upcoming', 'history'];
const OPEN_STATUSES = ['pending', 'confirmed'];
const ORDER_AGAIN_SIZE = 6;
// How many past items are checked for Order Again before giving up.
const ORDER_AGAIN_LOOKBACK = 50;

const ORDER_FIELDS = 'itemName category stallName pickupAddress pickupStart pickupEnd quantity unitPrice originalUnitPrice totalPrice status checkoutId createdAt';
const CARD_FIELDS = 'title description category isHalal originalPrice discountedPrice quantityAvailable soldCount pickupStart pickupEnd allergens otherAllergens imageUrl status createdAt vendor';

// Upcoming: still to collect. History: finished, cancelled, or the pickup window has passed.
function orderTabQuery(tab, customer, now = new Date()) {
  if (tab === 'upcoming') {
    return {
      filter: { customer, status: { $in: OPEN_STATUSES }, pickupEnd: { $gt: now } },
      sort: { pickupStart: 1, pickupEnd: 1, _id: 1 },
    };
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

module.exports = {
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
