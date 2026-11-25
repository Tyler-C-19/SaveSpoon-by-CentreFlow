const { windowLabel, timeLabel } = require('../src/services/notificationService');

const MINUTE_MS = 60 * 1000;

// Sample inbox entries. A vendor is the one selling the listing named.
const SAMPLE_NOTIFICATIONS = [
  { vendorOf: 'Mee Goreng Mamak', type: 'new_order', quantity: 2, minutesAgo: 20 },
  { vendorOf: 'Mee Goreng Mamak', type: 'new_order', quantity: 2, minutesAgo: 90, read: true },
  { customer: 0, type: 'favourite_back', kind: 'in stock', listing: 'Assorted Kuih Box', minutesAgo: 45 },
  { customer: 1, type: 'favourite_back', kind: 'on sale', listing: 'Chicken Sandwich', minutesAgo: 180, read: true },
];

function sampleNotifications(customers, listings, stalls, now = Date.now()) {
  const find = (title) => listings.find((listing) => listing.title === title);
  const stallOf = (listing) => stalls.find((stall) => String(stall._id) === String(listing.vendor));
  const docs = [];
  for (const sample of SAMPLE_NOTIFICATIONS) {
    const listing = find(sample.vendorOf ?? sample.listing);
    const stall = listing && stallOf(listing);
    if (!stall) continue;
    const createdAt = new Date(now - sample.minutesAgo * MINUTE_MS);
    const title = sample.vendorOf ? 'New order received' : `${listing.title} is back`;
    const body = sample.vendorOf
      ? `${sample.quantity} x ${listing.title}, pickup ${windowLabel(listing.pickupStart, listing.pickupEnd)}.`
      : `Back ${sample.kind} at ${stall.stallName}, pickup until ${timeLabel(listing.pickupEnd)}.`;
    docs.push({
      user: sample.vendorOf ? stall.user : customers[sample.customer]._id,
      type: sample.type,
      title,
      body,
      listingId: String(listing._id),
      createdAt,
      readAt: sample.read ? createdAt : undefined,
    });
  }
  return docs;
}

module.exports = { sampleNotifications, SAMPLE_NOTIFICATIONS };
