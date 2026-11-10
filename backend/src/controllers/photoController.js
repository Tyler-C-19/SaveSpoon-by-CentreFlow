const photoService = require('../services/photoService');
const { profileJson } = require('./userController');
const { cropError } = require('../validators/userValidators');
const { createUsageLimiter } = require('../services/usageLimiter');

const UNAVAILABLE = { error: 'Profile picture upload is unavailable. Try again later.', code: 'PHOTOS_UNAVAILABLE' };
const FULL_SQUARE = { x: 0, y: 0, width: 1, height: 1 };
const DAILY_CHANGES = 10;

// Uploads and reframes share one count per user.
const changeLimiter = createUsageLimiter({ limit: DAILY_CHANGES, windowMs: 24 * 60 * 60 * 1000 });

function limitReached(user, res) {
  const { allowed, retryAfterMs } = changeLimiter.take(user.id);
  if (allowed) return false;
  res.status(429).json({
    error: `You've changed your profile picture ${DAILY_CHANGES} times today. Try again in ${Math.ceil(retryAfterMs / 3600000)} h.`,
  });
  return true;
}

async function removeQuietly(id) {
  try {
    await photoService.remove(id);
  } catch (err) {
    console.error('Could not delete old picture:', err.message);
  }
}

// Multipart fields arrive as text.
function cropFromForm(body = {}) {
  const read = (key) => (body[key] === undefined ? undefined : Number(body[key]));
  const crop = { x: read('cropX'), y: read('cropY'), width: read('cropWidth'), height: read('cropHeight') };
  return Object.values(crop).every((value) => value === undefined) ? FULL_SQUARE : crop;
}

function applyFrame(user, crop) {
  user.photoCrop = crop;
  user.photoUrl = photoService.framedUrl(
    { id: user.photoId, width: user.photoWidth, height: user.photoHeight },
    crop
  );
}

async function setPhoto(req, res) {
  const crop = cropFromForm(req.body);
  const invalid = cropError(crop);
  if (invalid) return res.status(400).json({ error: invalid });
  if (!photoService.isConfigured()) return res.status(503).json(UNAVAILABLE);
  if (limitReached(req.user, res)) return undefined;

  let uploaded;
  try {
    uploaded = await photoService.upload(req.file.buffer);
  } catch (err) {
    console.error('Photo upload failed:', err.message);
    return res.status(503).json(UNAVAILABLE);
  }

  const oldId = req.user.photoId;
  req.user.photoId = uploaded.id;
  req.user.photoOriginalUrl = uploaded.originalUrl;
  req.user.photoWidth = uploaded.width;
  req.user.photoHeight = uploaded.height;
  applyFrame(req.user, crop);
  try {
    await req.user.save();
  } catch (err) {
    await removeQuietly(uploaded.id);
    throw err;
  }
  if (oldId) await removeQuietly(oldId);
  return res.json({ user: await profileJson(req.user) });
}

// Frames the current pic again without a new upload.
async function reframePhoto(req, res) {
  if (!req.user.photoId) return res.status(404).json({ error: 'Add a profile picture first.' });
  const crop = req.body?.crop;
  const invalid = cropError(crop);
  if (invalid) return res.status(400).json({ error: invalid });
  if (!photoService.isConfigured()) return res.status(503).json(UNAVAILABLE);
  if (limitReached(req.user, res)) return undefined;

  applyFrame(req.user, { x: crop.x, y: crop.y, width: crop.width, height: crop.height });
  await req.user.save();
  return res.json({ user: await profileJson(req.user) });
}

async function removePhoto(req, res) {
  const oldId = req.user.photoId;
  for (const field of ['photoUrl', 'photoId', 'photoOriginalUrl', 'photoWidth', 'photoHeight', 'photoCrop']) {
    req.user[field] = undefined;
  }
  await req.user.save();
  if (oldId) await removeQuietly(oldId);
  return res.json({ user: await profileJson(req.user) });
}

module.exports = { setPhoto, reframePhoto, removePhoto, removeQuietly };
