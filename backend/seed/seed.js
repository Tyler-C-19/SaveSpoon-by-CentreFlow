const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const { parseResetArgs, RESET_FLAG, CONFIRM_FLAG } = require('./resetGuard');
const { sampleListings, STALL_NAMES } = require('./sampleListings');

const LISTINGS_FLAG = '--listings';
const point = (lng, lat) => ({ type: 'Point', coordinates: [lng, lat] });

async function seedListingsOnly() {
  await mongoose.connect(process.env.MONGODB_URI);
  await Listing.init();

  if ((await Listing.countDocuments()) > 0) {
    console.log('Listings already exist, so nothing changed.');
    return;
  }
  const found = await Vendor.find({ stallName: { $in: STALL_NAMES } });
  const stalls = STALL_NAMES.map((name) => found.find((vendor) => vendor.stallName === name));
  if (stalls.includes(undefined)) {
    console.log('The seeded vendors are missing, so nothing changed.');
    return;
  }
  await Listing.insertMany(sampleListings(stalls));
  console.log('Seeded: 6 listings.');
}

async function seed() {
  if (process.argv.includes(LISTINGS_FLAG)) {
    await seedListingsOnly();
    return;
  }

  const { reset, blocked } = parseResetArgs(process.argv);
  if (blocked) {
    console.log('Nothing changed. --reset wipes data for the WHOLE TEAM, so warn them first.');
    console.log(`To go ahead run: npm run seed -- ${RESET_FLAG} ${CONFIRM_FLAG}`);
    return;
  }

  await mongoose.connect(process.env.MONGODB_URI);
  await Promise.all([User.init(), Vendor.init(), Listing.init()]);

  const seededUsers = { role: { $ne: 'admin' } };
  if ((await User.countDocuments(seededUsers)) > 0 && !reset) {
    console.log('Database already has data, so nothing changed.');
    console.log(`To wipe and reseed run: npm run seed -- ${RESET_FLAG} ${CONFIRM_FLAG}`);
    return;
  }
  if (reset) {
    await Listing.deleteMany({});
    await Vendor.deleteMany({});
    await User.deleteMany(seededUsers);
    console.log('Old users, vendors and listings cleared.');
  }

  const passwordHash = await bcrypt.hash('Password123', 10);
  const account = (fields) => ({ passwordHash, emailVerified: true, ...fields });

  const [vendorUser1, vendorUser2, vendorUser3] = await User.insertMany([
    account({ name: 'Pak Din', email: 'vendor1@savespoon.test', phone: '012-3456781', role: 'vendor' }),
    account({ name: 'Cendana Owner', email: 'vendor2@savespoon.test', phone: '012-3456782', role: 'vendor' }),
    account({ name: 'Kak Ina', email: 'vendor3@savespoon.test', phone: '012-3456783', role: 'vendor' }),
    account({ name: 'Customer One', email: 'customer1@savespoon.test', phone: '012-3456784', role: 'customer' }),
    account({ name: 'Customer Two', email: 'customer2@savespoon.test', phone: '012-3456785', role: 'customer' }),
  ]);

  const [stall1, stall2, stall3] = await Vendor.insertMany([
    {
      user: vendorUser1._id, stallName: 'Warung Pak Din', description: 'Nasi campur and home-style dishes',
      address: 'Cafeteria A, UTM Skudai', phone: '012-3456781', location: point(103.6385, 1.5590), verified: true,
    },
    {
      user: vendorUser2._id, stallName: 'Kafe Cendana', description: 'Mamak-style noodles and roti',
      address: 'Cafeteria B, UTM Skudai', phone: '012-3456782', location: point(103.6410, 1.5565), verified: true,
    },
    {
      user: vendorUser3._id, stallName: 'Roti Bakar Kak Ina', description: 'Toast, sandwiches and kuih',
      address: 'Kiosk near Library, UTM Skudai', phone: '012-3456783', location: point(103.6372, 1.5578), verified: false,
    },
  ]);

  await Listing.insertMany(sampleListings([stall1, stall2, stall3]));

  console.log('Seeded: 5 users, 3 vendors, 6 listings.');
  console.log('Test login password for every seeded account: Password123');
}

seed()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());
