const photoService = require('./photoService');

const FOLDER = 'savespoon/listing-photos';
const SEED_FOLDER = `${FOLDER}/seed`;
const FULL = { width: 1024, height: 768, crop: 'limit', quality: 'auto' };
const THUMB = { width: 480, height: 360, crop: 'limit', quality: 'auto' };
const RATIO = 4 / 3;

// The largest 4:3 area in the middle of a picture, in fractions of it.
function centredCrop(width, height) {
  if (width / height > RATIO) {
    const share = (height * RATIO) / width;
    return { x: (1 - share) / 2, y: 0, width: share, height: 1 };
  }
  const share = width / RATIO / height;
  return { x: 0, y: (1 - share) / 2, width: 1, height: share };
}

// Listing fields for a stored original and its framing.
function photoFields(original, crop) {
  return {
    imageUrl: photoService.framedUrl(original, crop, FULL),
    imageThumbUrl: photoService.framedUrl(original, crop, THUMB),
    imageId: original.id,
    imageOriginalUrl: original.originalUrl,
    imageWidth: original.width,
    imageHeight: original.height,
    imageCrop: crop,
  };
}

const PHOTO_FIELD_NAMES = [
  'imageUrl', 'imageThumbUrl', 'imageId', 'imageOriginalUrl', 'imageWidth', 'imageHeight', 'imageCrop',
];

// Sample photos are shared by seeded listings, so they are never deleted with one.
const isSeedPhoto = (id) => typeof id === 'string' && id.startsWith(`${SEED_FOLDER}/`);

async function removeQuietly(id) {
  if (!id || isSeedPhoto(id)) return;
  try {
    await photoService.remove(id);
  } catch (err) {
    console.error('Could not delete listing photo:', err.message);
  }
}

module.exports = { FOLDER, SEED_FOLDER, centredCrop, photoFields, PHOTO_FIELD_NAMES, isSeedPhoto, removeQuietly };
