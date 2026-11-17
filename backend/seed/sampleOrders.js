const { orderFields } = require('../src/services/orderService');

const SEED_REQUEST_PREFIX = 'seed-order-';

// Orders without daysAgo are for the current pickup window; their quantities must add up to
// each listing's soldCount in sampleListings.js. Orders with daysAgo are from earlier days.
const SAMPLE_ORDERS = [
  { customer: 0, title: 'Mee Goreng Mamak', quantity: 2 },
  { customer: 1, title: 'Mee Goreng Mamak', quantity: 2 },
  { customer: 0, title: 'Roti Canai (2 pcs) with Dhal', quantity: 1 },
  { customer: 1, title: 'Assorted Kuih Box', quantity: 3 },
  { customer: 0, title: 'Nasi Campur Set', quantity: 1, daysAgo: 1, status: 'completed' },
  { customer: 0, title: 'Chicken Sandwich', quantity: 2, daysAgo: 2 },
  { customer: 0, title: 'Ayam Goreng Rice', quantity: 1, daysAgo: 3, status: 'cancelled' },
];

const SAMPLE_CART_TITLES = ['Nasi Campur Set', 'Chicken Sandwich'];

const DAY_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;

function earlierDay(fields, daysAgo, status) {
  const pickupStart = new Date(fields.pickupStart.getTime() - daysAgo * DAY_MS);
  return {
    ...fields,
    pickupStart,
    pickupEnd: new Date(fields.pickupEnd.getTime() - daysAgo * DAY_MS),
    createdAt: new Date(pickupStart.getTime() - HOUR_MS),
    status: status ?? 'pending',
  };
}

function sampleOrders(customers, listings, stalls) {
  const find = (title) => listings.find((listing) => listing.title === title);
  const stallOf = (listing) => stalls.find((stall) => String(stall._id) === String(listing.vendor));

  return SAMPLE_ORDERS.map(({ customer, title, quantity, daysAgo, status }, index) => {
    const listing = find(title);
    const fields = orderFields({
      customer: customers[customer]._id,
      listing,
      vendor: stallOf(listing),
      quantity,
      requestId: `${SEED_REQUEST_PREFIX}${index + 1}`,
    });
    return daysAgo ? earlierDay(fields, daysAgo, status) : fields;
  });
}

function sampleCart(customer, listings, stalls) {
  const items = SAMPLE_CART_TITLES.map((title) => {
    const listing = listings.find((item) => item.title === title);
    const stall = stalls.find((item) => String(item._id) === String(listing.vendor));
    return {
      listing: listing._id,
      quantity: 1,
      itemName: listing.title,
      stallName: stall.stallName,
      unitPriceWhenAdded: listing.discountedPrice,
    };
  });
  return { customer: customer._id, items };
}

module.exports = { sampleOrders, sampleCart, SEED_REQUEST_PREFIX, SAMPLE_ORDERS };
