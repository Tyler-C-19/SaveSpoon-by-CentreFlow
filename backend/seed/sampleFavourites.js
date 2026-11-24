// Sample Favourites per seeded customer, by listing title. The last one listed is the newest.
const SAMPLE_FAVOURITES = [
  { customer: 0, titles: ['Assorted Kuih Box', 'Mee Goreng Mamak', 'Nasi Campur Set'] },
  { customer: 1, titles: ['Chicken Sandwich'] },
];

function sampleFavourites(customers, listings, now = Date.now()) {
  const docs = [];
  for (const { customer, titles } of SAMPLE_FAVOURITES) {
    titles.forEach((title, index) => {
      const listing = listings.find((item) => item.title === title);
      if (!listing) return;
      docs.push({
        customer: customers[customer]._id,
        listing: listing._id,
        createdAt: new Date(now - (titles.length - index) * 60 * 1000),
      });
    });
  }
  return docs;
}

module.exports = { sampleFavourites, SAMPLE_FAVOURITES };
