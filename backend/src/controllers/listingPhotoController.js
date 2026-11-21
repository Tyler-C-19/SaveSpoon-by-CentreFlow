const Listing = require('../models/Listing');
const photoService = require('../services/photoService');
const listingPhotos = require('../services/listingPhotoService');
const { cropError } = require('../validators/userValidators');
const { createUsageLimiter } = require('../services/usageLimiter');
const { findOwnListing, EDITABLE_STATUSES, PICKUP_OVER } = require('./listingController');

const UNAVAILABLE = { error: "Our server couldn't upload the photo right now. Please try again later.", code: 'PHOTOS_UNAVAILABLE' };
const BAD_FRAMING = 'Adjust the photo framing again.';
const NO_PHOTO = { error: 'Add a photo first.', code: 'NO_PHOTO' };
const DAILY_CHANGES = 20;

// Uploads and reframes share one count per vendor.
const changeLimiter = createUsageLimiter({ limit: DAILY_CHANGES, windowMs: 24 * 60 * 60 * 1000 });

function limitReached(user, res) {
  const { allowed, retryAfterMs } = changeLimiter.take(user.id);
  if (allowed) return false;
  res.status(429).json({
    error: `You've changed listing photos ${DAILY_CHANGES} times today. Try again in ${Math.ceil(retryAfterMs / 3600000)} h.`,
  });
  return true;
}

// Multipart fields arrive as text; no framing means the centred 4:3 area.
function cropFromForm(body = {}) {
  const read = (key) => (body[key] === undefined ? undefined : Number(body[key]));
  const crop = { x: read('cropX'), y: read('cropY'), width: read('cropWidth'), height: read('cropHeight') };
  return Object.values(crop).every((value) => value === undefined) ? null : crop;
}

const isOpen = (listing, now = new Date()) =>
  EDITABLE_STATUSES.includes(listing.status) && listing.pickupEnd > now;

// The vendor's own listing that can still be edited, or null after replying.
async function findEditable(req, res) {
  const found = await findOwnListing(req, res);
  if (!found) return null;
  if (!isOpen(found.listing)) {
    res.status(409).json(PICKUP_OVER);
    return null;
  }
  return found.listing;
}

// Saves the fields only if the listing is still there and open.
const saveFields = (listing, update) =>
  Listing.findOneAndUpdate(
    { _id: listing._id, vendor: listing.vendor, status: { $in: EDITABLE_STATUSES }, pickupEnd: { $gt: new Date() } },
    update,
    { returnDocument: 'after' }
  );

async function setPhoto(req, res) {
  const crop = cropFromForm(req.body);
  if (crop && cropError(crop)) return res.status(400).json({ error: BAD_FRAMING });
  const listing = await findEditable(req, res);
  if (!listing) return undefined;
  if (!photoService.isConfigured()) return res.status(503).json(UNAVAILABLE);
  if (limitReached(req.user, res)) return undefined;

  let uploaded;
  try {
    uploaded = await photoService.upload(req.file.buffer, { folder: listingPhotos.FOLDER });
  } catch (err) {
    console.error('Listing photo upload failed:', err.message);
    return res.status(503).json(UNAVAILABLE);
  }

  let updated;
  try {
    const fields = listingPhotos.photoFields(uploaded, crop ?? listingPhotos.centredCrop(uploaded.width, uploaded.height));
    updated = await saveFields(listing, { $set: fields });
  } catch (err) {
    await listingPhotos.removeQuietly(uploaded.id);
    throw err;
  }
  if (!updated) {
    await listingPhotos.removeQuietly(uploaded.id);
    return res.status(409).json(PICKUP_OVER);
  }
  if (listing.imageId && listing.imageId !== uploaded.id) await listingPhotos.removeQuietly(listing.imageId);
  return res.json({ listing: updated });
}

// Frames the current photo again without a new upload.
async function reframePhoto(req, res) {
  const crop = req.body?.crop;
  if (cropError(crop)) return res.status(400).json({ error: BAD_FRAMING });
  const listing = await findEditable(req, res);
  if (!listing) return undefined;
  if (!listing.imageId || !listing.imageWidth || !listing.imageHeight) return res.status(404).json(NO_PHOTO);
  if (!photoService.isConfigured()) return res.status(503).json(UNAVAILABLE);
  if (limitReached(req.user, res)) return undefined;

  const original = {
    id: listing.imageId,
    originalUrl: listing.imageOriginalUrl,
    width: listing.imageWidth,
    height: listing.imageHeight,
  };
  const framing = { x: crop.x, y: crop.y, width: crop.width, height: crop.height };
  const updated = await saveFields(listing, { $set: listingPhotos.photoFields(original, framing) });
  if (!updated) return res.status(409).json(PICKUP_OVER);
  return res.json({ listing: updated });
}

async function removePhoto(req, res) {
  const listing = await findEditable(req, res);
  if (!listing) return undefined;
  if (!listing.imageId && !listing.imageUrl) return res.json({ listing });

  const unset = Object.fromEntries(listingPhotos.PHOTO_FIELD_NAMES.map((field) => [field, '']));
  const updated = await saveFields(listing, { $unset: unset });
  if (!updated) return res.status(409).json(PICKUP_OVER);
  await listingPhotos.removeQuietly(listing.imageId);
  return res.json({ listing: updated });
}

module.exports = { setPhoto, reframePhoto, removePhoto, DAILY_CHANGES };
