const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const mongoose = require('mongoose');

const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const placesService = require('../src/services/placesService');

async function refreshVendorLocations() {
  const vendors = await Vendor.find({ placeId: { $exists: true, $ne: null } });
  const failed = [];
  let refreshed = 0;

  for (const vendor of vendors) {
    try {
      const { lat, lng } = await placesService.locate(vendor.placeId);
      const location = { type: 'Point', coordinates: [lng, lat] };
      await Vendor.updateOne({ _id: vendor._id }, { location });
      await Listing.updateMany({ vendor: vendor._id }, { location });
      refreshed += 1;
    } catch (err) {
      failed.push({ stallName: vendor.stallName, reason: err.message });
    }
  }
  return { refreshed, failed };
}

async function main() {
  await mongoose.connect(process.env.MONGODB_URI);
  const { refreshed, failed } = await refreshVendorLocations();
  console.log(`Refreshed ${refreshed} vendor location(s).`);
  failed.forEach(({ stallName, reason }) => console.error(`Could not refresh ${stallName}: ${reason}`));
  if (failed.length) process.exitCode = 1;
}

if (require.main === module) {
  main()
    .catch((err) => {
      console.error(err.message);
      process.exitCode = 1;
    })
    .finally(() => mongoose.disconnect());
}

module.exports = { refreshVendorLocations };
