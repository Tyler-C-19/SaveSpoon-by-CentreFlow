const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const Order = require('../src/models/Order');
const Cart = require('../src/models/Cart');
const SalesRecord = require('../src/models/SalesRecord');
const Favourite = require('../src/models/Favourite');
const Notification = require('../src/models/Notification');
const { parseResetArgs, RESET_FLAG, CONFIRM_FLAG } = require('./resetGuard');
const { sampleSalesRecords } = require('./sampleSalesRecords');
const { sampleFavourites } = require('./sampleFavourites');
const { sampleNotifications } = require('./sampleNotifications');
const { sampleListings, STALL_NAMES } = require('./sampleListings');
const { sampleOrders, sampleCart, SEED_REQUEST_PREFIX } = require('./sampleOrders');
const { sampleSearchListings, sampleRefreshOps } = require('./sampleSearchListings');
const { applySeedImages } = require('./sampleImages');
const { SAMPLE_ACCOUNTS, missingAccounts, missingStalls } = require('./sampleAccounts');
const photoService = require('../src/services/photoService');

const LISTINGS_FLAG = '--listings';
const SEARCH_SAMPLES_FLAG = '--search-samples';
const SALES_RECORDS_FLAG = '--sales-records';
const IMAGES_FLAG = '--images';
const RESTORE_ACCOUNTS_FLAG = '--restore-accounts';
const FAVOURITES_FLAG = '--favourites';
const NOTIFICATIONS_FLAG = '--notifications';
const CUSTOMER_EMAILS = ['customer1@savespoon.test', 'customer2@savespoon.test'];
const VENDOR_EMAILS = ['vendor1@savespoon.test', 'vendor2@savespoon.test', 'vendor3@savespoon.test'];

async function addOrdersAndCart(customers, listings, stalls) {
  await Order.deleteMany({ requestId: { $regex: `^${SEED_REQUEST_PREFIX}` } });
  await Order.insertMany(sampleOrders(customers, listings, stalls));
  const { customer, items } = sampleCart(customers[0], listings, stalls);
  await Cart.findOneAndUpdate({ customer }, { $set: { items } }, { upsert: true });
}

// Sample photos for the given listings; skipped without Cloudinary keys.
async function addImages(listings) {
  if (!photoService.isConfigured()) {
    console.log('Cloudinary keys are missing, so no sample photos were added.');
    return;
  }
  let counts;
  try {
    counts = await applySeedImages(listings, {
      photoService,
      updateListing: (id, fields) => Listing.updateOne({ _id: id }, { $set: fields }),
    });
  } catch (err) {
    console.log(`Sample photos failed (${err.message}); everything else is seeded. Try npm run seed -- --images later.`);
    return;
  }
  console.log(
    `Sample photos: ${counts.updated} listings updated, ${counts.uploaded} uploaded, `
      + `${counts.alreadyStored} already on Cloudinary.`
  );
}

async function seededStalls() {
  // Found by login email, since vendors may have renamed their stalls.
  const users = await User.find({ email: { $in: VENDOR_EMAILS } });
  const found = await Vendor.find({ user: { $in: users.map((user) => user._id) } });
  return VENDOR_EMAILS.map((email) => {
    const user = users.find((item) => item.email === email);
    return user && found.find((vendor) => String(vendor.user) === String(user._id));
  });
}

// Adds sample photos to the existing seeded listings; nothing else changes.
async function seedImagesOnly() {
  await mongoose.connect(process.env.MONGODB_URI);
  const stalls = (await seededStalls()).filter(Boolean);
  if (!stalls.length) {
    console.log('The seeded vendors are missing, so nothing changed.');
    return;
  }
  await addImages(await Listing.find({ vendor: { $in: stalls.map((stall) => stall._id) } }));
}

async function seedListingsOnly() {
  await mongoose.connect(process.env.MONGODB_URI);
  await Promise.all([Listing.init(), Order.init(), Cart.init()]);

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
  const listings = await Listing.insertMany(sampleListings(stalls));
  await addImages(listings);

  const accounts = await User.find({ email: { $in: CUSTOMER_EMAILS } });
  const customers = CUSTOMER_EMAILS.map((email) => accounts.find((user) => user.email === email));
  if (customers.includes(undefined)) {
    console.log('Seeded: 6 listings. The seeded customers are missing, so no orders were added.');
    return;
  }
  await addOrdersAndCart(customers, listings, stalls);
  const records = await SalesRecord.insertMany(sampleSalesRecords(listings, stalls));
  console.log(`Seeded: 6 listings, 4 orders, ${records.length} sales records, 1 cart.`);
}

async function seedSearchSamples() {
  await mongoose.connect(process.env.MONGODB_URI);
  await Listing.init();

  const found = await Vendor.find({ stallName: { $in: STALL_NAMES } });
  const stalls = STALL_NAMES.map((name) => found.find((vendor) => vendor.stallName === name));
  if (stalls.includes(undefined)) {
    console.log('The seeded vendors are missing, so nothing changed.');
    return;
  }
  const samples = [...sampleListings(stalls), ...sampleSearchListings(stalls)];
  const result = await Listing.bulkWrite(sampleRefreshOps(samples));
  console.log(`Search samples: ${result.upsertedCount} added, ${result.matchedCount} refreshed. Other listings unchanged.`);
}

// Adds sample sales records to the existing seeded listings, once.
async function seedSalesRecordsOnly() {
  await mongoose.connect(process.env.MONGODB_URI);
  await SalesRecord.init();

  const stalls = await seededStalls();
  if (stalls.includes(undefined)) {
    console.log('The seeded vendors are missing, so nothing changed.');
    return;
  }
  const listings = await Listing.find({ vendor: { $in: stalls.map((stall) => stall._id) } });
  let records;
  try {
    records = sampleSalesRecords(listings, stalls);
  } catch {
    console.log('The sample listings are missing, so nothing changed.');
    return;
  }
  if ((await SalesRecord.countDocuments({ listing: { $in: records.map((record) => record.listing) } })) > 0) {
    console.log('Sample sales records already exist, so nothing changed.');
    return;
  }
  await SalesRecord.insertMany(records);
  console.log(`Seeded: ${records.length} sales records. Other data unchanged.`);
}

// Adds the sample Favourites to the seeded customers, once.
async function seedFavouritesOnly() {
  await mongoose.connect(process.env.MONGODB_URI);
  await Favourite.init();

  const accounts = await User.find({ email: { $in: CUSTOMER_EMAILS } });
  const customers = CUSTOMER_EMAILS.map((email) => accounts.find((user) => user.email === email));
  const stalls = await seededStalls();
  if (customers.includes(undefined) || stalls.includes(undefined)) {
    console.log('The seeded customers or vendors are missing, so nothing changed.');
    return;
  }
  if ((await Favourite.countDocuments({ customer: { $in: customers.map((user) => user._id) } })) > 0) {
    console.log('The seeded customers already have Favourites, so nothing changed.');
    return;
  }
  const listings = await Listing.find({ vendor: { $in: stalls.map((stall) => stall._id) } });
  const favourites = await Favourite.insertMany(sampleFavourites(customers, listings));
  console.log(`Seeded: ${favourites.length} Favourites. Other data unchanged.`);
}

// Adds the sample notifications to the seeded accounts' inboxes, once.
async function seedNotificationsOnly() {
  await mongoose.connect(process.env.MONGODB_URI);
  await Notification.init();

  const accounts = await User.find({ email: { $in: CUSTOMER_EMAILS } });
  const customers = CUSTOMER_EMAILS.map((email) => accounts.find((user) => user.email === email));
  const stalls = await seededStalls();
  if (customers.includes(undefined) || stalls.includes(undefined)) {
    console.log('The seeded customers or vendors are missing, so nothing changed.');
    return;
  }
  const users = [...customers.map((user) => user._id), ...stalls.map((stall) => stall.user)];
  if ((await Notification.countDocuments({ user: { $in: users } })) > 0) {
    console.log('The seeded accounts already have notifications, so nothing changed.');
    return;
  }
  const listings = await Listing.find({ vendor: { $in: stalls.map((stall) => stall._id) } });
  const notes = await Notification.insertMany(sampleNotifications(customers, listings, stalls));
  console.log(`Seeded: ${notes.length} notifications. Other data unchanged.`);
}

// Re-creates only the sample accounts that are gone, and any sample vendor's
// stall that is gone, with that stall's sample listings.
async function restoreAccounts() {
  await mongoose.connect(process.env.MONGODB_URI);
  await Promise.all([User.init(), Vendor.init(), Listing.init()]);

  const emails = SAMPLE_ACCOUNTS.map((account) => account.user.email);
  const existing = await User.find({ email: { $in: emails } });
  const missing = missingAccounts(existing.map((user) => user.email));
  const passwordHash = await bcrypt.hash('Password123', 10);
  const added = missing.length
    ? await User.insertMany(missing.map(({ user }) => ({ passwordHash, emailVerified: true, ...user })))
    : [];

  const users = [...existing, ...added];
  const stalls = await Vendor.find({ user: { $in: users.map((user) => user._id) } });
  const vendors = missingStalls(users, stalls);
  const restored = vendors.length
    ? await Vendor.insertMany(vendors.map(({ stall, userId }) => ({ user: userId, ...stall })))
    : [];

  // sampleListings takes the three stalls in seed order; only restored stalls get listings.
  const slots = [0, 1, 2].map((index) => {
    const position = vendors.findIndex((account) => account.index === index);
    return position === -1 ? { _id: null } : restored[position];
  });
  const fresh = sampleListings(slots).filter((listing) => listing.vendor);
  const listings = fresh.length ? await Listing.insertMany(fresh) : [];
  if (listings.length) await addImages(listings);

  if (!added.length && !restored.length) {
    console.log('Every sample account and stall exists, so nothing changed.');
    return;
  }
  if (added.length) console.log(`Restored accounts: ${added.map((user) => user.email).join(', ')}.`);
  if (restored.length) console.log(`Restored stalls: ${restored.map((stall) => stall.stallName).join(', ')}.`);
  console.log(`Added ${listings.length} sample listings. Other data unchanged.`);
  if (added.length) console.log('Test login password for restored accounts: Password123');
}

async function seed() {
  if (process.argv.includes(RESTORE_ACCOUNTS_FLAG)) {
    await restoreAccounts();
    return;
  }
  if (process.argv.includes(FAVOURITES_FLAG)) {
    await seedFavouritesOnly();
    return;
  }
  if (process.argv.includes(NOTIFICATIONS_FLAG)) {
    await seedNotificationsOnly();
    return;
  }
  if (process.argv.includes(IMAGES_FLAG)) {
    await seedImagesOnly();
    return;
  }
  if (process.argv.includes(SALES_RECORDS_FLAG)) {
    await seedSalesRecordsOnly();
    return;
  }
  if (process.argv.includes(SEARCH_SAMPLES_FLAG)) {
    await seedSearchSamples();
    return;
  }
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
  await Promise.all([User.init(), Vendor.init(), Listing.init(), Order.init(), Cart.init(), SalesRecord.init(), Favourite.init(), Notification.init()]);

  const seededUsers = { role: { $ne: 'admin' } };
  if ((await User.countDocuments(seededUsers)) > 0 && !reset) {
    console.log('Database already has data, so nothing changed.');
    console.log(`To wipe and reseed run: npm run seed -- ${RESET_FLAG} ${CONFIRM_FLAG}`);
    return;
  }
  if (reset) {
    await Notification.deleteMany({});
    await Favourite.deleteMany({});
    await Cart.deleteMany({});
    await Order.deleteMany({});
    await SalesRecord.deleteMany({});
    await Listing.deleteMany({});
    await Vendor.deleteMany({});
    await User.deleteMany(seededUsers);
    console.log('Old users, vendors, listings, orders, sales records, carts, Favourites and notifications cleared.');
  }

  const passwordHash = await bcrypt.hash('Password123', 10);
  const account = (fields) => ({ passwordHash, emailVerified: true, ...fields });

  const [vendorUser1, vendorUser2, vendorUser3, customer1, customer2] = await User.insertMany(
    SAMPLE_ACCOUNTS.map(({ user }) => account(user))
  );

  const vendorUsers = [vendorUser1, vendorUser2, vendorUser3];
  const [stall1, stall2, stall3] = await Vendor.insertMany(
    SAMPLE_ACCOUNTS.filter((item) => item.stall).map(({ stall }, index) => ({ user: vendorUsers[index]._id, ...stall }))
  );

  const stalls = [stall1, stall2, stall3];
  const listings = await Listing.insertMany(sampleListings(stalls));
  await addImages(listings);
  await addOrdersAndCart([customer1, customer2], listings, stalls);
  const records = await SalesRecord.insertMany(sampleSalesRecords(listings, stalls));
  const favourites = await Favourite.insertMany(sampleFavourites([customer1, customer2], listings));
  const notes = await Notification.insertMany(sampleNotifications([customer1, customer2], listings, stalls));

  console.log(
    `Seeded: 5 users, 3 vendors, 6 listings, 4 orders, ${records.length} sales records, 1 cart, `
      + `${favourites.length} Favourites, ${notes.length} notifications.`
  );
  console.log('Test login password for every seeded account: Password123');
}

seed()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());
