const Cart = require('../models/Cart');
const Listing = require('../models/Listing');
const Vendor = require('../models/Vendor');
const {
  unavailableProblem,
  GONE,
  LISTING_GONE,
  SOLD_OUT,
  PICKUP_ENDED,
  roundMoney,
} = require('./orderService');

const EARTH_RADIUS_KM = 6371;

const REASONS = new Map([
  [LISTING_GONE, 'No longer available'],
  [SOLD_OUT, 'Sold out'],
  [PICKUP_ENDED, 'Pickup ended'],
]);

const toRadians = (degrees) => (degrees * Math.PI) / 180;

function distanceKm([lng1, lat1], [lng2, lat2]) {
  const latGap = toRadians(lat2 - lat1);
  const lngGap = toRadians(lng2 - lng1);
  const a = Math.sin(latGap / 2) ** 2
    + Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(lngGap / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}

function farthestApartKm(points) {
  let farthest = 0;
  points.forEach((point, index) => {
    points.slice(index + 1).forEach((other) => {
      farthest = Math.max(farthest, distanceKm(point, other));
    });
  });
  return farthest;
}

function pickupWarnings(entries) {
  const warnings = [];
  const stalls = new Map(entries.map(({ vendor }) => [String(vendor._id), vendor]));
  if (stalls.size > 1) {
    const km = farthestApartKm([...stalls.values()].map((vendor) => vendor.location.coordinates));
    warnings.push(`Heads up: you'll collect from ${stalls.size} stalls, up to ${km.toFixed(1)} km apart.`);
  }
  if (entries.length > 1) {
    const latestStart = Math.max(...entries.map(({ listing }) => listing.pickupStart.getTime()));
    const earliestEnd = Math.min(...entries.map(({ listing }) => listing.pickupEnd.getTime()));
    if (latestStart >= earliestEnd) {
      warnings.push("Heads up: these pickup times don't overlap, so you'll need more than one trip.");
    }
  }
  return warnings;
}

async function loadEntries(items) {
  const listingIds = items.map((item) => item.listing);
  const listings = listingIds.length ? await Listing.find({ _id: { $in: listingIds } }) : [];
  const vendorIds = [...new Set(listings.map((listing) => String(listing.vendor)))];
  const vendors = vendorIds.length ? await Vendor.find({ _id: { $in: vendorIds } }) : [];
  const listingById = new Map(listings.map((listing) => [String(listing._id), listing]));
  const vendorById = new Map(vendors.map((vendor) => [String(vendor._id), vendor]));

  return items.map((item) => {
    const listing = listingById.get(String(item.listing));
    const vendor = listing && vendorById.get(String(listing.vendor));
    return vendor ? { item, listing, vendor } : { item };
  });
}

function itemView({ item, listing, vendor }, now) {
  const problem = vendor ? unavailableProblem(listing, now) : GONE;
  const base = {
    listingId: String(item.listing),
    itemName: item.itemName,
    stallName: item.stallName,
    category: listing?.category ?? null,
    available: !problem,
    reason: problem ? REASONS.get(problem.code) : null,
    notices: [],
  };
  if (problem) {
    return { ...base, quantity: item.quantity, unitPrice: item.unitPriceWhenAdded, lineTotal: 0 };
  }

  const notices = [];
  if (item.quantity > listing.quantityAvailable) {
    item.quantity = listing.quantityAvailable;
    notices.push(`Only ${item.quantity} left, so your quantity is now ${item.quantity}.`);
  }
  if (item.unitPriceWhenAdded !== listing.discountedPrice) {
    notices.push(
      `Price changed from RM ${item.unitPriceWhenAdded.toFixed(2)} to RM ${listing.discountedPrice.toFixed(2)}.`
    );
  }
  return {
    ...base,
    quantity: item.quantity,
    unitPrice: listing.discountedPrice,
    lineTotal: roundMoney(listing.discountedPrice * item.quantity),
    stockLeft: listing.quantityAvailable,
    pickupStart: listing.pickupStart,
    pickupEnd: listing.pickupEnd,
    pickupAddress: vendor.address,
    notices,
  };
}

// Re-checks each item against its listing and saves any quantity it had to lower.
async function viewCart(cart, now = new Date()) {
  if (!cart) return { view: { items: [], total: 0, warnings: [] }, entries: [] };

  const entries = await loadEntries(cart.items);
  const before = cart.items.map((item) => item.quantity);
  const items = entries.map((entry) => itemView(entry, now));
  if (cart.items.some((item, index) => item.quantity !== before[index])) await cart.save();

  const liveEntries = entries.filter((entry, index) => items[index].available);
  return {
    view: {
      items,
      total: roundMoney(items.reduce((sum, item) => sum + item.lineTotal, 0)),
      warnings: pickupWarnings(liveEntries),
    },
    entries: liveEntries,
  };
}

function findOrCreateCart(customer) {
  return Cart.findOneAndUpdate(
    { customer },
    { $setOnInsert: { customer } },
    { upsert: true, returnDocument: 'after', setDefaultsOnInsert: true }
  );
}

module.exports = { viewCart, findOrCreateCart, distanceKm, pickupWarnings };
