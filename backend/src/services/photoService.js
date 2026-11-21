const { v2: cloudinary } = require('cloudinary');

const FOLDER = 'savespoon/profile-photos';
const SIZE = 512;
const ORIGINAL_LIMIT = 1024;

class PhotoError extends Error {}

function isConfigured() {
  return Boolean(
    process.env.CLOUDINARY_CLOUD_NAME && process.env.CLOUDINARY_API_KEY && process.env.CLOUDINARY_API_SECRET
  );
}

function configure() {
  if (!isConfigured()) throw new PhotoError('Cloudinary keys are missing');
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
    secure: true,
  });
}

const asOriginal = (result) => ({
  id: result.public_id,
  originalUrl: result.secure_url,
  width: result.width,
  height: result.height,
});

// Stores the original (up to 1024 px). Resolves to { id, originalUrl, width, height }.
// A fixed publicId (a full path) replaces whatever was stored under it.
function upload(buffer, { folder = FOLDER, publicId } = {}) {
  return new Promise((resolve, reject) => {
    configure();
    const stream = cloudinary.uploader.upload_stream(
      {
        resource_type: 'image',
        transformation: [{ width: ORIGINAL_LIMIT, height: ORIGINAL_LIMIT, crop: 'limit' }],
        // A fixed publicId is the full path, so it isn't put under the folder again.
        ...(publicId ? { public_id: publicId, overwrite: true } : { folder }),
      },
      (err, result) => {
        if (err || !result) return reject(new PhotoError(err?.message ?? 'Upload failed'));
        return resolve(asOriginal(result));
      }
    );
    stream.end(buffer);
  });
}

// An already stored original, or null when there is none.
async function findUploaded(id) {
  configure();
  try {
    return asOriginal(await cloudinary.api.resource(id, { resource_type: 'image' }));
  } catch (err) {
    if (err?.error?.http_code === 404 || err?.http_code === 404) return null;
    throw new PhotoError(err?.error?.message ?? err?.message ?? 'Lookup failed');
  }
}

// The framed picture, cut from the original by Cloudinary when first viewed.
// crop is in fractions of the original; size defaults to the profile square.
function framedUrl({ id, width, height }, crop, size = { width: SIZE, height: SIZE, crop: 'fill' }) {
  configure();
  const px = (fraction, total) => Math.round(fraction * total);
  return cloudinary.url(id, {
    secure: true,
    transformation: [
      {
        crop: 'crop',
        x: px(crop.x, width),
        y: px(crop.y, height),
        width: Math.max(1, px(crop.width, width)),
        height: Math.max(1, px(crop.height, height)),
      },
      size,
    ],
  });
}

async function remove(id) {
  if (!id) return;
  configure();
  await cloudinary.uploader.destroy(id, { resource_type: 'image' });
}

module.exports = { upload, findUploaded, framedUrl, remove, isConfigured, PhotoError };
