// These tests replace Cloudinary and database calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const Order = require('../src/models/Order');
const SalesRecord = require('../src/models/SalesRecord');
const photoService = require('../src/services/photoService');
const listingPhotos = require('../src/services/listingPhotoService');
const { signToken } = require('../src/services/tokenService');

const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(32)]);
const inHours = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000);

const makeUser = (role) => new User({ name: 'Test', email: `${role}-${Math.random()}@example.com`, role, emailVerified: true });
const vendorId = new mongoose.Types.ObjectId();

const makeListing = (overrides = {}) => new Listing({
  vendor: vendorId,
  title: 'Nasi Lemak',
  category: 'Rice',
  isHalal: true,
  originalPrice: 8,
  discountedPrice: 4.5,
  quantityAvailable: 4,
  pickupStart: inHours(-1),
  pickupEnd: inHours(2),
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
  ...overrides,
});

let uploads;
let removed;
let framed;
let saved;

function signedInAs(user) {
  mock.method(User, 'findById', () => query(user));
  return signToken(user.id);
}

function vendorWith(listing) {
  const token = signedInAs(makeUser('vendor'));
  mock.method(Vendor, 'findOne', async () => ({ _id: vendorId, stallName: 'Warung Test', address: 'UTM' }));
  mock.method(Listing, 'findOne', async () => listing);
  return token;
}

function photoForm(crop = null) {
  const form = new FormData();
  form.append('photo', new Blob([PNG], { type: 'image/png' }), 'food.png');
  if (crop) {
    form.append('cropX', String(crop.x));
    form.append('cropY', String(crop.y));
    form.append('cropWidth', String(crop.width));
    form.append('cropHeight', String(crop.height));
  }
  return form;
}

const url = (listing) => `/api/listings/${listing?.id ?? new mongoose.Types.ObjectId()}/photo`;

beforeEach(() => {
  mock.restoreAll();
  uploads = [];
  removed = [];
  framed = [];
  saved = [];
  mock.method(photoService, 'isConfigured', () => true);
  mock.method(photoService, 'upload', async (buffer, options) => {
    uploads.push(options);
    return { id: `savespoon/listing-photos/new-${uploads.length}`, originalUrl: 'https://cdn/original.jpg', width: 1200, height: 900 };
  });
  mock.method(photoService, 'framedUrl', (original, crop, size) => {
    framed.push({ original, crop, size });
    return `https://cdn/${size.width}.jpg`;
  });
  mock.method(photoService, 'remove', async (id) => removed.push(id));
  mock.method(Listing, 'findOneAndUpdate', async (filter, update) => {
    saved.push({ filter, update });
    return { _id: filter._id, ...update.$set };
  });
  mock.method(console, 'error', () => {});
});

test('photo endpoints return 401 when not logged in', async () => {
  for (const method of ['PUT', 'PATCH', 'DELETE']) {
    assert.equal((await call(url(), { method })).status, 401, method);
  }
});

test('photo endpoints return 403 for other roles', async () => {
  for (const role of ['customer', 'admin']) {
    const token = signedInAs(makeUser(role));
    assert.equal((await call(url(), { method: 'DELETE', token })).status, 403, role);
    mock.restoreAll();
  }
});

test("another vendor's listing returns 404 and uploads nothing", async () => {
  const token = vendorWith(null);
  const res = await call(url(), { method: 'PUT', token, form: photoForm() });
  assert.equal(res.status, 404);
  assert.equal(uploads.length, 0);
});

test('uploading saves both sizes, the original and a centred 4:3 framing', async () => {
  const listing = makeListing();
  const token = vendorWith(listing);

  const res = await call(url(listing), { method: 'PUT', token, form: photoForm() });

  assert.equal(res.status, 200);
  assert.deepEqual(uploads, [{ folder: 'savespoon/listing-photos' }]);
  assert.equal(res.body.listing.imageUrl, 'https://cdn/1024.jpg');
  assert.equal(res.body.listing.imageThumbUrl, 'https://cdn/480.jpg');
  assert.equal(res.body.listing.imageOriginalUrl, 'https://cdn/original.jpg');
  // 1200 x 900 is already 4:3, so the whole picture is used.
  assert.deepEqual(res.body.listing.imageCrop, { x: 0, y: 0, width: 1, height: 1 });
  assert.equal(String(saved[0].filter.vendor), String(vendorId));
  assert.deepEqual(removed, []);
});

test('the chosen framing is used, and the old photo is deleted', async () => {
  const listing = makeListing({ imageId: 'savespoon/listing-photos/old', imageUrl: 'https://old' });
  const token = vendorWith(listing);
  const crop = { x: 0.1, y: 0.1, width: 0.8, height: 0.8 };

  const res = await call(url(listing), { method: 'PUT', token, form: photoForm(crop) });

  assert.equal(res.status, 200);
  assert.deepEqual(framed[0].crop, crop);
  assert.deepEqual(removed, ['savespoon/listing-photos/old']);
});

test('a sample photo is never deleted when replaced', async () => {
  const listing = makeListing({ imageId: 'savespoon/listing-photos/seed/nasi-lemak' });
  const token = vendorWith(listing);
  assert.equal((await call(url(listing), { method: 'PUT', token, form: photoForm() })).status, 200);
  assert.deepEqual(removed, []);
});

test('a bad framing is rejected before uploading', async () => {
  const listing = makeListing();
  const token = vendorWith(listing);
  const res = await call(url(listing), { method: 'PUT', token, form: photoForm({ x: 0.5, y: 0, width: 0.8, height: 1 }) });
  assert.equal(res.status, 400);
  assert.equal(uploads.length, 0);
});

test('an ended listing can\'t change its photo', async () => {
  const listing = makeListing({ pickupStart: inHours(-3), pickupEnd: inHours(-1) });
  const token = vendorWith(listing);
  const res = await call(url(listing), { method: 'PUT', token, form: photoForm() });
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'PICKUP_ENDED');
  assert.equal(uploads.length, 0);
});

test('the upload is deleted again if the listing ended or went meanwhile', async () => {
  const listing = makeListing();
  const token = vendorWith(listing);
  Listing.findOneAndUpdate.mock.mockImplementation(async () => null);

  const res = await call(url(listing), { method: 'PUT', token, form: photoForm() });

  assert.equal(res.status, 409);
  assert.deepEqual(removed, ['savespoon/listing-photos/new-1']);
});

test('without Cloudinary the photo step says uploads are unavailable', async () => {
  const listing = makeListing();
  const token = vendorWith(listing);
  photoService.isConfigured.mock.mockImplementation(() => false);

  const res = await call(url(listing), { method: 'PUT', token, form: photoForm() });

  assert.equal(res.status, 503);
  assert.equal(res.body.error, "Our server couldn't upload the photo right now. Please try again later.");
});

test('a failed upload changes nothing', async () => {
  const listing = makeListing({ imageId: 'savespoon/listing-photos/old' });
  const token = vendorWith(listing);
  photoService.upload.mock.mockImplementation(async () => { throw new photoService.PhotoError('down'); });

  const res = await call(url(listing), { method: 'PUT', token, form: photoForm() });

  assert.equal(res.status, 503);
  assert.equal(saved.length, 0);
  assert.deepEqual(removed, []);
});

test('re-framing uses the stored original without uploading', async () => {
  const listing = makeListing({
    imageId: 'savespoon/listing-photos/old', imageOriginalUrl: 'https://orig', imageWidth: 800, imageHeight: 800,
  });
  const token = vendorWith(listing);
  const crop = { x: 0, y: 0.125, width: 1, height: 0.75 };

  const res = await call(url(listing), { method: 'PATCH', token, body: { crop } });

  assert.equal(res.status, 200);
  assert.equal(uploads.length, 0);
  assert.deepEqual(framed[0].original, { id: 'savespoon/listing-photos/old', originalUrl: 'https://orig', width: 800, height: 800 });
  assert.deepEqual(saved[0].update.$set.imageCrop, crop);
  assert.deepEqual(removed, []);
});

test('re-framing without a photo returns 404', async () => {
  const listing = makeListing();
  const token = vendorWith(listing);
  const res = await call(url(listing), { method: 'PATCH', token, body: { crop: { x: 0, y: 0, width: 1, height: 1 } } });
  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'NO_PHOTO');
});

test('removing clears every photo field and deletes the file', async () => {
  const listing = makeListing({ imageId: 'savespoon/listing-photos/old', imageUrl: 'https://old' });
  const token = vendorWith(listing);

  const res = await call(url(listing), { method: 'DELETE', token });

  assert.equal(res.status, 200);
  assert.deepEqual(Object.keys(saved[0].update.$unset).sort(), [...listingPhotos.PHOTO_FIELD_NAMES].sort());
  assert.deepEqual(removed, ['savespoon/listing-photos/old']);
});

test('uploads and re-framings share 20 a day per vendor, and removing still works', async () => {
  const listing = makeListing({
    imageId: 'savespoon/listing-photos/old', imageOriginalUrl: 'https://orig', imageWidth: 800, imageHeight: 600,
  });
  const token = vendorWith(listing);
  const reframe = { method: 'PATCH', token, body: { crop: { x: 0, y: 0, width: 1, height: 1 } } };

  for (let i = 0; i < 19; i += 1) {
    assert.equal((await call(url(listing), { method: 'PUT', token, form: photoForm() })).status, 200);
  }
  assert.equal((await call(url(listing), reframe)).status, 200);

  const res = await call(url(listing), { method: 'PUT', token, form: photoForm() });
  assert.equal(res.status, 429);
  assert.match(res.body.error, /changed listing photos 20 times today/);
  assert.equal((await call(url(listing), reframe)).status, 429);
  assert.equal((await call(url(listing), { method: 'DELETE', token })).status, 200);
});

test('creating or editing a listing can\'t set the photo', async () => {
  const token = vendorWith(null);
  mock.method(Listing, 'exists', async () => null);
  const create = mock.method(Listing, 'create', async (doc) => doc);
  Vendor.findOne.mock.mockImplementation(async () => ({ _id: vendorId, location: { coordinates: [103.6, 1.5] } }));

  await call('/api/listings', {
    method: 'POST',
    token,
    body: {
      title: 'Kuih', category: 'Desserts', isHalal: true, originalPrice: 5, discountedPrice: 3,
      quantityAvailable: 3, pickupStart: inHours(0.5).toISOString(), pickupEnd: inHours(2).toISOString(),
      imageUrl: 'https://evil', imageId: 'x',
    },
  });

  const [doc] = create.mock.calls[0].arguments;
  assert.equal(doc.imageUrl, undefined);
  assert.equal(doc.imageId, undefined);
});

test('deleting a listing deletes its photo', async () => {
  const listing = makeListing({ imageId: 'savespoon/listing-photos/old' });
  const token = vendorWith(listing);
  mock.method(Order, 'countDocuments', async () => 0);
  mock.method(SalesRecord, 'create', async (doc) => ({ _id: new mongoose.Types.ObjectId(), ...doc }));
  mock.method(Listing, 'deleteOne', async () => ({ deletedCount: 1 }));

  const res = await call(`/api/listings/${listing.id}`, { method: 'DELETE', token });

  assert.equal(res.status, 200);
  assert.deepEqual(removed, ['savespoon/listing-photos/old']);
});

test('customers get the card photo but not the stored original', async () => {
  const listing = makeListing({
    imageUrl: 'https://cdn/1024.jpg', imageThumbUrl: 'https://cdn/480.jpg', imageId: 'secret', imageOriginalUrl: 'https://orig',
  });
  const token = signedInAs(makeUser('customer'));
  mock.method(Listing, 'findById', async () => listing);
  mock.method(Vendor, 'findById', async () => ({ _id: vendorId, stallName: 'Warung Test', address: 'UTM' }));

  const res = await call(`/api/listings/${listing.id}`, { token });

  assert.equal(res.status, 200);
  assert.equal(res.body.listing.imageUrl, 'https://cdn/1024.jpg');
  assert.equal(res.body.listing.imageThumbUrl, 'https://cdn/480.jpg');
  assert.equal('imageId' in res.body.listing, false);
  assert.equal('imageOriginalUrl' in res.body.listing, false);
});

test('a relisted listing keeps its photo', async () => {
  const listing = makeListing({
    pickupStart: inHours(-4), pickupEnd: inHours(-2), imageUrl: 'https://cdn/1024.jpg', imageId: 'savespoon/listing-photos/a',
  });
  const token = vendorWith(listing);
  mock.method(SalesRecord, 'create', async (doc) => doc);
  mock.method(SalesRecord, 'aggregate', async () => []);
  Listing.findOneAndUpdate.mock.mockImplementation(async (filter, update) => {
    saved.push({ filter, update });
    return listing;
  });
  mock.method(Listing, 'findById', async () => listing);

  const start = new Date(Math.ceil(Date.now() / 1800000) * 1800000);
  const res = await call(`/api/listings/${listing.id}/relist`, {
    method: 'POST',
    token,
    body: { quantityAvailable: 5, pickupStart: start.toISOString(), pickupEnd: new Date(start.getTime() + 7200000).toISOString() },
  });

  assert.equal(res.status, 200);
  const changed = Object.keys(saved[0].update.$set);
  assert.equal(changed.some((key) => key.startsWith('image')), false);
  assert.equal(uploads.length, 0);
  assert.deepEqual(removed, []);
});

test('the centred 4:3 area of wide and tall pictures', () => {
  const wide = listingPhotos.centredCrop(1600, 900);
  assert.equal(wide.y, 0);
  assert.equal(wide.height, 1);
  assert.ok(Math.abs(wide.width - 0.75) < 1e-9);
  assert.ok(Math.abs(wide.x - 0.125) < 1e-9);
  const tall = listingPhotos.centredCrop(900, 1600);
  assert.equal(tall.x, 0);
  assert.ok(Math.abs((tall.width * 900) / (tall.height * 1600) - 4 / 3) < 1e-9);
});

test('a new order copies the card photo, and older listings without one copy nothing', () => {
  const { orderFields } = require('../src/services/orderService');
  const vendor = { _id: vendorId, stallName: 'Warung Test', address: 'UTM' };
  const withPhoto = makeListing({ imageThumbUrl: 'https://cdn/480.jpg' });
  const fields = orderFields({ customer: 'c1', listing: withPhoto, vendor, quantity: 1, requestId: 'r1' });
  assert.equal(fields.imageThumbUrl, 'https://cdn/480.jpg');
  assert.equal(new Order(fields).imageThumbUrl, 'https://cdn/480.jpg');
  const without = orderFields({ customer: 'c1', listing: makeListing(), vendor, quantity: 1, requestId: 'r2' });
  assert.equal(without.imageThumbUrl, undefined);
});
