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
const OTHER_STALLS_SIZE = 6;
const TOP_RESULTS = 3;
const SEARCH_MAX_LENGTH = 50;
const PAGE_PATTERN = /^[1-9]\d{0,4}$/;

// Points per search word, by where it is found.
const SEARCH_POINTS = { titleWordStart: 10, titleInside: 6, stall: 4, address: 4, category: 3, description: 1, titleStartsWithSearch: 20 };
// Shorter words, such as a single letter, don't count as naming a stall.
const STALL_WORD_MIN = 3;

const availableMatch = (now, stock = { $gt: 0 }) => ({
  $match: { status: 'active', quantityAvailable: stock, pickupEnd: { $gt: now } },
});

const withStall = [
  { $lookup: { from: Vendor.collection.name, localField: 'vendor', foreignField: '_id', as: 'vendorProfile' } },
  { $unwind: '$vendorProfile' },
];

const publicFields = {
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
};

function availablePipeline({ now, stock, sort, skip = 0, limit }) {
  return [availableMatch(now, stock), { $sort: sort }, ...withStall, { $skip: skip }, { $limit: limit }, publicFields];
}

const escapeRegex = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function searchWords(raw) {
  const text = raw.trim().replace(/\s+/g, ' ');
  const words = [...new Set(text.toLowerCase().split(' '))];
  return { text, words };
}

const NOT_WORD = '[^a-z0-9]';
const matches = (field, regex) => ({ $regexMatch: { input: { $ifNull: [field, ''] }, regex, options: 'i' } });
const pointsIf = (condition, points) => ({ $cond: [condition, points, 0] });

function wordScore(word) {
  const safe = escapeRegex(word);
  return {
    $add: [
      {
        $cond: [
          matches('$title', `(^|${NOT_WORD})${safe}`),
          SEARCH_POINTS.titleWordStart,
          pointsIf(matches('$title', safe), SEARCH_POINTS.titleInside),
        ],
      },
      pointsIf(matches('$vendorProfile.stallName', safe), SEARCH_POINTS.stall),
      pointsIf(matches('$vendorProfile.address', safe), SEARCH_POINTS.address),
      pointsIf(matches('$category', safe), SEARCH_POINTS.category),
      pointsIf(matches('$description', `(^|${NOT_WORD})${safe}($|${NOT_WORD})`), SEARCH_POINTS.description),
    ],
  };
}

function searchStages(now, { text, words }) {
  const wordFields = Object.fromEntries(words.map((word, index) => [`_word${index}`, wordScore(word)]));
  const wordKeys = words.map((_, index) => `$_word${index}`);
  return [
    availableMatch(now),
    ...withStall,
    { $addFields: wordFields },
    { $match: { $expr: { $and: wordKeys.map((key) => ({ $gt: [key, 0] })) } } },
    {
      $addFields: {
        _score: {
          $add: [
            ...wordKeys,
            pointsIf(matches('$title', `^${escapeRegex(text)}`), SEARCH_POINTS.titleStartsWithSearch),
          ],
        },
      },
    },
  ];
}

const searchFields = { $project: { ...publicFields.$project, pickupAddress: '$vendorProfile.address' } };

function namesStall(listings, words) {
  const stallWords = words.filter((word) => word.length >= STALL_WORD_MIN);
  return listings.some((item) => stallWords.some((word) => item.stallName?.toLowerCase().includes(word)));
}

async function otherStalls(now, search, firstPage) {
  if (!namesStall(firstPage.slice(0, TOP_RESULTS), search.words)) return [];
  const categories = [...new Set(firstPage.slice(0, TOP_RESULTS).map((item) => item.category).filter(Boolean))];
  if (categories.length === 0) return [];

  const [found] = await Listing.aggregate([
    ...searchStages(now, search),
    { $group: { _id: null, vendors: { $addToSet: '$vendor' } } },
  ]);
  return Listing.aggregate([
    { $match: { ...availableMatch(now).$match, category: { $in: categories }, vendor: { $nin: found?.vendors ?? [] } } },
    { $sort: { quantityAvailable: 1, pickupEnd: 1, _id: 1 } },
    ...withStall,
    { $limit: OTHER_STALLS_SIZE },
    searchFields,
  ]);
}

async function search(req, res) {
  const { q, page = '1' } = req.query;
  if (typeof page !== 'string' || !PAGE_PATTERN.test(page)) {
    return res.status(400).json({ error: 'Page must be a whole number.' });
  }
  const length = typeof q === 'string' ? q.trim().replace(/\s+/g, ' ').length : 0;
  if (length < 1 || length > SEARCH_MAX_LENGTH) {
    return res.status(400).json({ error: `Enter 1 to ${SEARCH_MAX_LENGTH} characters to search.` });
  }

  const now = new Date();
  const words = searchWords(q);
  const found = await Listing.aggregate([
    ...searchStages(now, words),
    { $sort: { _score: -1, createdAt: -1, _id: -1 } },
    { $skip: (Number(page) - 1) * PAGE_SIZE },
    { $limit: PAGE_SIZE + 1 },
    searchFields,
  ]);
  const listings = found.slice(0, PAGE_SIZE);
  const body = { listings, hasMore: found.length > PAGE_SIZE };
  if (page === '1') body.otherStalls = await otherStalls(now, words, listings);
  return res.json(body);
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

module.exports = { createListing, getAvailable, getRunningOut, search, getDetails, getMine, suggestAllergens };
