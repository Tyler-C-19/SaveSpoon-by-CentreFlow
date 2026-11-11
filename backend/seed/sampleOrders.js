const { orderFields } = require('../src/services/orderService');

const SEED_REQUEST_PREFIX = 'seed-order-';

// Quantities here must add up to each listing's soldCount in sampleListings.js.
const SAMPLE_ORDERS = [
  { customer: 0, title: 'Mee Goreng Mamak', quantity: 2 },
  { customer: 1, title: 'Mee Goreng Mamak', quantity: 2 },
  { customer: 0, title: 'Roti Canai (2 pcs) with Dhal', quantity: 1 },
  { customer: 1, title: 'Assorted Kuih Box', quantity: 3 },
];

const SAMPLE_CART_TITLES = ['Nasi Campur Set', 'Chicken Sandwich'];

function sampleOrders(customers, listings, stalls) {
  const find = (title) => listings.find((listing) => listing.title === title);
  const stallOf = (listing) => stalls.find((stall) => String(stall._id) === String(listing.vendor));

  return SAMPLE_ORDERS.map(({ customer, title, quantity }, index) => {
    const listing = find(title);
    return orderFields({
      customer: customers[customer]._id,
      listing,
      vendor: stallOf(listing),
      quantity,
      requestId: `${SEED_REQUEST_PREFIX}${index + 1}`,
    });
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
