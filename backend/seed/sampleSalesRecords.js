const DAY_MS = 24 * 60 * 60 * 1000;

// Earlier rounds of two sample listings, as if they had been relisted on previous days.
const SAMPLE_ROUNDS = [
  { title: 'Nasi Campur Set', daysAgo: 1, sold: 9, leftover: 1 },
  { title: 'Nasi Campur Set', daysAgo: 2, sold: 6, leftover: 4 },
  { title: 'Mee Goreng Mamak', daysAgo: 1, sold: 12, leftover: 0 },
];

function sampleSalesRecords(listings, stalls) {
  return SAMPLE_ROUNDS.map(({ title, daysAgo, sold, leftover }) => {
    const listing = listings.find((item) => item.title === title);
    const stall = stalls.find((item) => String(item._id) === String(listing.vendor));
    const earlier = (date) => new Date(new Date(date).getTime() - daysAgo * DAY_MS);
    return {
      listing: listing._id,
      vendor: stall._id,
      stallName: stall.stallName,
      pickupAddress: stall.address,
      itemName: listing.title,
      category: listing.category,
      originalPrice: listing.originalPrice,
      discountedPrice: listing.discountedPrice,
      pickupStart: earlier(listing.pickupStart),
      pickupEnd: earlier(listing.pickupEnd),
      stockOffered: sold + leftover,
      sold,
      leftover,
      recordedAt: earlier(listing.pickupEnd),
    };
  });
}

module.exports = { sampleSalesRecords, SAMPLE_ROUNDS };
