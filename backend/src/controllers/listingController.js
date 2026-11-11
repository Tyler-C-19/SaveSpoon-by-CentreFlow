const Listing = require('../models/Listing');
const Vendor = require('../models/Vendor');
const { findLiveListing, unavailableProblem, GONE, LISTING_GONE } = require('../services/orderService');
const geminiService = require('../services/geminiService');
const { descriptionError } = require('../validators/vendorValidators');
const { listingError, titleError } = require('../validators/listingValidators');
const { createUsageLimiter } = require('../services/usageLimiter');
const { normaliseAllergens, LOW_STOCK_LIMIT } = require('../models/listingOptions');
const { NO_PROFILE } = require('./vendorController');

const suggestionLimiter = createUsageLimiter({ limit: 10, windowMs: 60 * 60 * 1000 });

const PAGE_SIZE = 20;
const RUNNING_OUT_SIZE = 6;
const PAGE_PATTERN = /^[1-9]\d{0,4}$/;

function availablePipeline({ now, stock = { $gt: 0 }, sort, skip = 0, limit }) {
  return [
    { $match: { status: 'active', quantityAvailable: stock, pickupEnd: { $gt: now } } },
    { $sort: sort },
    { $lookup: { from: Vendor.collection.name, localField: 'vendor', foreignField: '_id', as: 'vendorProfile' } },
    { $unwind: '$vendorProfile' },
    { $skip: skip },
    { $limit: limit },
    {
      $project: {
        title: 1,
        description: 1,
        category: 1,
        isHalal: 1,
        originalPrice: 1,
        discountedPrice: 1,
        quantityAvailable: 1,
        soldCount: 1,
        pickupStart: 1,
        pickupEnd: 1,
        allergens: 1,
        otherAllergens: 1,
        imageUrl: 1,
        status: 1,
        createdAt: 1,
        stallName: '$vendorProfile.stallName',
      },
    },
  ];
}

async function getAvailable(req, res) {
  const { page = '1' } = req.query;
  if (typeof page !== 'string' || !PAGE_PATTERN.test(page)) {
    return res.status(400).json({ error: 'Page must be a whole number.' });
  }

  const found = await Listing.aggregate(
    availablePipeline({
      now: new Date(),
      sort: { createdAt: -1, _id: -1 },
      skip: (Number(page) - 1) * PAGE_SIZE,
      limit: PAGE_SIZE + 1,
    })
  );
  return res.json({ listings: found.slice(0, PAGE_SIZE), hasMore: found.length > PAGE_SIZE });
}

async function getRunningOut(req, res) {
  const listings = await Listing.aggregate(
    availablePipeline({
      now: new Date(),
      stock: { $gt: 0, $lte: LOW_STOCK_LIMIT },
      sort: { quantityAvailable: 1, pickupEnd: 1, _id: 1 },
      limit: RUNNING_OUT_SIZE,
    })
  );
  return res.json({ listings });
}

async function getDetails(req, res) {
  const { listing, vendor } = await findLiveListing(req.params.id);
  if (!listing || unavailableProblem(listing)?.code === LISTING_GONE) {
    const { status, ...problem } = GONE;
    return res.status(status).json(problem);
  }

  const { vendor: vendorId, location, ...details } = listing.toObject();
  return res.json({
    listing: { ...details, stallName: vendor.stallName, pickupAddress: vendor.address },
  });
}

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

module.exports = { createListing, getAvailable, getRunningOut, getDetails, getMine, suggestAllergens };
