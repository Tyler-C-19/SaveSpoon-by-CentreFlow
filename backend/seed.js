require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const User = require('./models/User');
const Vendor = require('./models/Vendor');
const Listing = require('./models/Listing');

const hoursFromNow = (h) => new Date(Date.now() + h * 60 * 60 * 1000);
const point = (lng, lat) => ({ type: 'Point', coordinates: [lng, lat] });

async function seed() {
  await mongoose.connect(process.env.MONGODB_URI);
  await Promise.all([User.init(), Vendor.init(), Listing.init()]);

  const reset = process.argv.includes('--reset');
  if ((await User.countDocuments()) > 0 && !reset) {
    console.log('Database already has data. To wipe and reseed run: npm run seed -- --reset');
    return;
  }
  if (reset) {
    await Listing.deleteMany({});
    await Vendor.deleteMany({});
    await User.deleteMany({});
    console.log('Old users, vendors and listings cleared.');
  }

  const passwordHash = await bcrypt.hash('Password123', 10);

  const [admin, vendorUser1, vendorUser2, vendorUser3, student1, student2] = await User.insertMany([
    { name: 'Admin User', email: 'admin@savespoon.test', passwordHash, role: 'admin' },
    { name: 'Pak Din', email: 'vendor1@savespoon.test', passwordHash, role: 'vendor' },
    { name: 'Cendana Owner', email: 'vendor2@savespoon.test', passwordHash, role: 'vendor' },
    { name: 'Kak Ina', email: 'vendor3@savespoon.test', passwordHash, role: 'vendor' },
    { name: 'Student One', email: 'student1@savespoon.test', passwordHash, role: 'student' },
    { name: 'Student Two', email: 'student2@savespoon.test', passwordHash, role: 'student' },
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

  const make = (stall, fields) => ({ vendor: stall._id, location: stall.location, ...fields });

  await Listing.insertMany([
    make(stall1, {
      title: 'Nasi Campur Set', description: 'Rice with 2 dishes and a vegetable',
      originalPrice: 8, discountedPrice: 4.5, quantityAvailable: 6,
      pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(3), allergens: ['egg'],
    }),
    make(stall1, {
      title: 'Ayam Goreng Rice', description: 'Fried chicken with rice and sambal',
      originalPrice: 7, discountedPrice: 4, quantityAvailable: 4,
      pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(3), allergens: ['soy'],
    }),
    make(stall2, {
      title: 'Mee Goreng Mamak', description: 'Spicy fried noodles with egg',
      originalPrice: 6, discountedPrice: 3.5, quantityAvailable: 8,
      pickupStart: hoursFromNow(2), pickupEnd: hoursFromNow(4), allergens: ['gluten', 'egg', 'soy'],
    }),
    make(stall2, {
      title: 'Roti Canai (2 pcs) with Dhal', description: 'Fresh roti canai with dhal',
      originalPrice: 3.5, discountedPrice: 2, quantityAvailable: 10,
      pickupStart: hoursFromNow(2), pickupEnd: hoursFromNow(4), allergens: ['gluten', 'milk'],
    }),
    make(stall3, {
      title: 'Chicken Sandwich', description: 'Grilled chicken, lettuce and mayo',
      originalPrice: 5, discountedPrice: 3, quantityAvailable: 5,
      pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(2), allergens: ['gluten', 'egg'],
    }),
    make(stall3, {
      title: 'Assorted Kuih Box', description: 'Box of 6 mixed kuih',
      originalPrice: 6, discountedPrice: 3.5, quantityAvailable: 0,
      pickupStart: hoursFromNow(1), pickupEnd: hoursFromNow(3), allergens: ['coconut', 'gluten'], status: 'sold_out',
    }),
  ]);

  console.log('Seeded: 6 users, 3 vendors, 6 listings.');
  console.log('Test login password for every seeded account: Password123');
}

seed()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());
