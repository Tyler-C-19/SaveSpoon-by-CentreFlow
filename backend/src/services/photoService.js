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

// Stores the original (up to 1024 px). Resolves to { id, originalUrl, width, height }.
function upload(buffer) {
  return new Promise((resolve, reject) => {
    configure();
    const stream = cloudinary.uploader.upload_stream(
      {
        folder: FOLDER,
        resource_type: 'image',
        transformation: [{ width: ORIGINAL_LIMIT, height: ORIGINAL_LIMIT, crop: 'limit' }],
      },
      (err, result) => {
        if (err || !result) return reject(new PhotoError(err?.message ?? 'Upload failed'));
        return resolve({
          id: result.public_id,
          originalUrl: result.secure_url,
          width: result.width,
          height: result.height,
        });
      }
    );
    stream.end(buffer);
  });
}

// The framed square, cut from the original by Cloudinary when first viewed.
// crop is in fractions of the original.
function framedUrl({ id, width, height }, crop) {
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
      { width: SIZE, height: SIZE, crop: 'fill' },
    ],
  });
}

async function remove(id) {
  if (!id) return;
  configure();
  await cloudinary.uploader.destroy(id, { resource_type: 'image' });
}

module.exports = { upload, framedUrl, remove, isConfigured, PhotoError };
