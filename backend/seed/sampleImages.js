// Sample listing photos from Pixabay (Content License, no attribution required),
// stored on Cloudinary under fixed names so running the seed again uploads nothing.
const fs = require('fs/promises');
const path = require('path');
const listingPhotos = require('../src/services/listingPhotoService');

const IMAGE_DIR = path.join(__dirname, 'images');

// Listing title -> file in seed/images. Titles without one keep the category icon.
const SAMPLE_IMAGES = {
  'Nasi Lemak Ayam': 'nasi-lemak-ayam.jpg',
  'Nasi Lemak Bungkus': 'nasi-lemak-bungkus.jpg',
  'Ayam Goreng Rice': 'ayam-goreng-rice.jpg',
  'Ayam Penyet': 'ayam-penyet.jpg',
  'Nasi Goreng Kampung': 'nasi-goreng-kampung.jpg',
  'Roti Jala (3 pcs) with Curry': 'roti-jala.jpg',
  'Chicken Sandwich': 'chicken-sandwich.jpg',
  'Assorted Kuih Box': 'kuih-box.jpg',
  'Kuey Teow Goreng': 'kuey-teow-goreng.jpg',
};

const seedPhotoId = (file) => `${listingPhotos.SEED_FOLDER}/${path.parse(file).name}`;

// Sets sample photos on the given listings. A vendor's own photo is left alone.
// Returns counts of uploads, photos already stored, and listings updated.
async function applySeedImages(listings, { photoService, updateListing, readFile = fs.readFile }) {
  const originals = new Map();
  const counts = { uploaded: 0, alreadyStored: 0, updated: 0 };

  async function originalFor(file) {
    if (originals.has(file)) return originals.get(file);
    const id = seedPhotoId(file);
    let original = await photoService.findUploaded(id);
    if (original) {
      counts.alreadyStored += 1;
    } else {
      original = await photoService.upload(await readFile(path.join(IMAGE_DIR, file)), { publicId: id });
      counts.uploaded += 1;
    }
    originals.set(file, original);
    return original;
  }

  for (const listing of listings) {
    const file = SAMPLE_IMAGES[listing.title];
    if (!file) continue;
    if (listing.imageId && !listingPhotos.isSeedPhoto(listing.imageId)) continue;
    const original = await originalFor(file);
    const fields = listingPhotos.photoFields(original, listingPhotos.centredCrop(original.width, original.height));
    await updateListing(listing._id, fields);
    counts.updated += 1;
  }
  return counts;
}

module.exports = { SAMPLE_IMAGES, IMAGE_DIR, seedPhotoId, applySeedImages };
