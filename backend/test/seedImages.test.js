// Checks the sample photos with stand-ins for Cloudinary; nothing is uploaded and
// nothing touches the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const mongoose = require('mongoose');

const { SAMPLE_IMAGES, IMAGE_DIR, seedPhotoId, applySeedImages } = require('../seed/sampleImages');
const { sampleListings } = require('../seed/sampleListings');
const { sampleSearchListings } = require('../seed/sampleSearchListings');
const listingPhotos = require('../src/services/listingPhotoService');
const realPhotoService = require('../src/services/photoService');

beforeEach(() => {
  mock.restoreAll();
  mock.method(realPhotoService, 'framedUrl', (original, crop, size) => `https://cdn/${original.id}/${size.width}.jpg`);
});

const stalls = ['Warung Pak Din', 'Kafe Cendana', 'Roti Bakar Kak Ina'].map((stallName) => ({
  _id: new mongoose.Types.ObjectId(),
  stallName,
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
}));

function fakeCloudinary(stored = new Set()) {
  const uploads = [];
  return {
    uploads,
    photoService: {
      findUploaded: async (id) => (stored.has(id) ? { id, originalUrl: `https://cdn/${id}.jpg`, width: 800, height: 533 } : null),
      upload: async (buffer, { publicId }) => {
        uploads.push(publicId);
        stored.add(publicId);
        return { id: publicId, originalUrl: `https://cdn/${publicId}.jpg`, width: 800, height: 600 };
      },
    },
  };
}

const listing = (title, extra = {}) => ({ _id: new mongoose.Types.ObjectId(), title, ...extra });

test('every sample photo file exists, is a small JPEG and names a seeded listing', () => {
  const titles = [...sampleListings(stalls), ...sampleSearchListings(stalls)].map((item) => item.title);
  for (const [title, file] of Object.entries(SAMPLE_IMAGES)) {
    assert.ok(titles.includes(title), `${title} is a seeded listing`);
    const bytes = fs.readFileSync(path.join(IMAGE_DIR, file));
    assert.equal(bytes[0], 0xff, `${file} is a JPEG`);
    assert.ok(bytes.length < 200 * 1024, `${file} is under 200 KB`);
  }
});

test('sample photos go in the seed folder, which is never deleted with a listing', () => {
  const id = seedPhotoId('nasi-lemak-ayam.jpg');
  assert.equal(id, 'savespoon/listing-photos/seed/nasi-lemak-ayam');
  assert.equal(listingPhotos.isSeedPhoto(id), true);
  assert.equal(listingPhotos.isSeedPhoto('savespoon/listing-photos/abc'), false);
});

test('photos are uploaded once and set with both sizes and a centred 4:3 framing', async () => {
  const { photoService, uploads } = fakeCloudinary();
  const updates = [];
  const listings = [listing('Nasi Lemak Ayam'), listing('Ayam Penyet'), listing('Mee Goreng Mamak')];

  const counts = await applySeedImages(listings, {
    photoService,
    updateListing: async (id, fields) => updates.push({ id, fields }),
    readFile: async () => Buffer.from([0xff, 0xd8, 0xff]),
  });

  assert.deepEqual(uploads, [
    'savespoon/listing-photos/seed/nasi-lemak-ayam',
    'savespoon/listing-photos/seed/ayam-penyet',
  ]);
  assert.deepEqual(counts, { uploaded: 2, alreadyStored: 0, updated: 2 });
  const [first] = updates;
  assert.equal(first.fields.imageUrl, 'https://cdn/savespoon/listing-photos/seed/nasi-lemak-ayam/1024.jpg');
  assert.equal(first.fields.imageThumbUrl, 'https://cdn/savespoon/listing-photos/seed/nasi-lemak-ayam/480.jpg');
  assert.deepEqual(first.fields.imageCrop, { x: 0, y: 0, width: 1, height: 1 });
});

test('running again uploads nothing', async () => {
  const stored = new Set();
  const first = fakeCloudinary(stored);
  const deps = { updateListing: async () => {}, readFile: async () => Buffer.alloc(3) };
  await applySeedImages([listing('Kuey Teow Goreng')], { ...deps, photoService: first.photoService });

  const again = fakeCloudinary(stored);
  const counts = await applySeedImages([listing('Kuey Teow Goreng')], { ...deps, photoService: again.photoService });

  assert.deepEqual(again.uploads, []);
  assert.deepEqual(counts, { uploaded: 0, alreadyStored: 1, updated: 1 });
});

test("a vendor's own photo is left alone", async () => {
  const { photoService, uploads } = fakeCloudinary();
  const updates = [];
  await applySeedImages([listing('Chicken Sandwich', { imageId: 'savespoon/listing-photos/own' })], {
    photoService,
    updateListing: async (id, fields) => updates.push(fields),
    readFile: async () => Buffer.alloc(3),
  });
  assert.deepEqual(uploads, []);
  assert.deepEqual(updates, []);
});
