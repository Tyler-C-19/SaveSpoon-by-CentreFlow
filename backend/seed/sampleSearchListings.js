// Extra listings for trying search and "Other stalls you might like".
function sampleSearchListings([stall1, stall2, stall3]) {
  const make = (stall, fields) => ({ vendor: stall._id, location: stall.location, isHalal: true, ...fields });

  return [
    make(stall1, {
      title: 'Mee Rebus', description: 'Yellow noodles in thick sweet potato gravy with egg',
      category: 'Noodles', originalPrice: 6, discountedPrice: 3.5, quantityAvailable: 5, allergens: ['gluten', 'egg'],
    }),
    make(stall1, {
      title: 'Bubur Cha Cha', description: 'Sweet potato and yam in coconut milk',
      category: 'Desserts', originalPrice: 4, discountedPrice: 2, quantityAvailable: 3, allergens: ['coconut'],
    }),
    make(stall1, {
      title: 'Nasi Lemak Ayam', description: 'Coconut rice with fried chicken, sambal and ikan bilis',
      category: 'Rice', originalPrice: 9, discountedPrice: 5, quantityAvailable: 2, allergens: ['coconut', 'fish', 'belacan'],
    }),
    make(stall2, {
      title: 'Nasi Goreng Kampung', description: 'Village-style fried rice with ikan bilis and egg',
      category: 'Rice', originalPrice: 7, discountedPrice: 4, quantityAvailable: 4, allergens: ['fish', 'egg', 'belacan'],
    }),
    make(stall2, {
      title: 'Teh Tarik', description: 'Pulled milk tea',
      category: 'Drinks', originalPrice: 2.5, discountedPrice: 1.5, quantityAvailable: 12, allergens: ['milk'],
    }),
    make(stall2, {
      title: 'Kuey Teow Goreng', description: 'Fried flat noodles with prawns and egg',
      category: 'Noodles', originalPrice: 7, discountedPrice: 4, quantityAvailable: 7, allergens: ['shellfish', 'egg', 'soy'],
    }),
    make(stall3, {
      title: 'Nasi Lemak Bungkus', description: 'Wrapped coconut rice with fried egg and sambal',
      category: 'Rice', originalPrice: 4, discountedPrice: 2.5, quantityAvailable: 4, allergens: ['coconut', 'egg', 'belacan'],
    }),
    make(stall3, {
      title: 'Kaya Toast', description: 'Toast with kaya and butter',
      category: 'Snacks', originalPrice: 3, discountedPrice: 1.5, quantityAvailable: 9, allergens: ['gluten', 'egg', 'milk', 'coconut'],
    }),
    make(stall3, {
      title: 'Ayam Penyet', description: 'Smashed fried chicken with rice, tofu, tempeh and sambal',
      category: 'Rice', originalPrice: 9, discountedPrice: 5.5, quantityAvailable: 3, allergens: ['soy', 'belacan'],
    }),
  ];
}

const REFRESH_START_HOURS = 1;
const REFRESH_END_HOURS = 8;
const REFRESHED_FIELDS = ['pickupStart', 'pickupEnd', 'quantityAvailable', 'status'];

// Adds each sample if it is missing, otherwise restocks it and opens a new pickup window.
function sampleRefreshOps(listings, now = Date.now()) {
  const hoursFromNow = (hours) => new Date(now + hours * 60 * 60 * 1000);
  return listings.map((listing) => {
    const kept = Object.fromEntries(Object.entries(listing).filter(([key]) => !REFRESHED_FIELDS.includes(key)));
    return {
      updateOne: {
        filter: { vendor: listing.vendor, title: listing.title },
        update: {
          $set: {
            pickupStart: hoursFromNow(REFRESH_START_HOURS),
            pickupEnd: hoursFromNow(REFRESH_END_HOURS),
            quantityAvailable: listing.quantityAvailable,
            status: listing.status ?? 'active',
          },
          $setOnInsert: kept,
        },
        upsert: true,
      },
    };
  });
}

module.exports = { sampleSearchListings, sampleRefreshOps };
