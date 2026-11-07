const Listing = require('../models/Listing');
const Vendor = require('../models/Vendor');
const geminiService = require('../services/geminiService');
const { descriptionError } = require('../validators/vendorValidators');
const { listingError, titleError } = require('../validators/listingValidators');
const { createUsageLimiter } = require('../services/usageLimiter');
const { normaliseAllergens } = require('../models/listingOptions');
const { NO_PROFILE } = require('./vendorController');

const suggestionLimiter = createUsageLimiter({ limit: 10, windowMs: 60 * 60 * 1000 });

async function createListing(req, res) {
  const invalid = listingError(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const vendor = await Vendor.findOne({ user: req.user._id });
  if (!vendor) return res.status(404).json(NO_PROFILE);

  const { title, description, category, isHalal, originalPrice, discountedPrice } = req.body;
  const listing = await Listing.create({
    vendor: vendor._id,
    title: title.trim(),
    description: description?.trim(),
    category,
    isHalal,
    originalPrice,
    discountedPrice,
    quantityAvailable: req.body.quantityAvailable,
    pickupStart: new Date(req.body.pickupStart),
    pickupEnd: new Date(req.body.pickupEnd),
    ...normaliseAllergens(req.body.allergens, req.body.otherAllergens),
    location: { type: 'Point', coordinates: vendor.location.coordinates },
  });
  return res.status(201).json({ listing });
}

async function getMine(req, res) {
  const vendor = await Vendor.findOne({ user: req.user._id });
  if (!vendor) return res.status(404).json(NO_PROFILE);

  const listings = await Listing.find({ vendor: vendor._id }).sort({ createdAt: -1 });
  return res.json({ listings });
}

async function suggestAllergens(req, res) {
  const { title, description } = req.body ?? {};
  const invalid = titleError(title) || descriptionError(description);
  if (invalid) return res.status(400).json({ error: invalid });

  const { allowed, retryAfterMs } = suggestionLimiter.take(req.user.id);
  if (!allowed) {
    const minutes = Math.ceil(retryAfterMs / 60000);
    return res.status(429).json({
      error: `You've reached the AI suggestion limit. Try again in ${minutes} min, or choose the allergens yourself.`,
    });
  }

  try {
    return res.json(await geminiService.suggestAllergens(title.trim(), description?.trim()));
  } catch (err) {
    console.error('Allergen suggestion failed:', err.message);
    return res.status(503).json({ error: 'SaveSpoon AI is temporarily unavailable. Try again later or enter allergens manually.' });
  }
}

module.exports = { createListing, getMine, suggestAllergens };
