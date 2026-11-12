const Order = require('../models/Order');
const Listing = require('../models/Listing');

const ACTIVE_ORDER_STATUSES = ['pending', 'confirmed'];

// Pending or confirmed, with a pickup window that hasn't closed.
function activeOrderFilter(owner, now = new Date()) {
  return { ...owner, status: { $in: ACTIVE_ORDER_STATUSES }, pickupEnd: { $gt: now } };
}

// One a customer could still order.
function activeListingFilter(vendorId, now = new Date()) {
  return { vendor: vendorId, status: 'active', quantityAvailable: { $gt: 0 }, pickupEnd: { $gt: now } };
}

function countActiveOrders(owner) {
  return Order.countDocuments(activeOrderFilter(owner));
}

function countActiveListings(vendorId) {
  return Listing.countDocuments(activeListingFilter(vendorId));
}

function countListings(vendorId) {
  return Listing.countDocuments({ vendor: vendorId });
}

module.exports = {
  ACTIVE_ORDER_STATUSES, activeOrderFilter, activeListingFilter, countActiveOrders, countActiveListings, countListings,
};
