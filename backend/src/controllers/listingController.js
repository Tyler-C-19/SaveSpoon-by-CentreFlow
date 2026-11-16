const Listing = require('../models/Listing');
const Vendor = require('../models/Vendor');
const { findLiveListing, unavailableProblem, GONE, LISTING_GONE } = require('../services/orderService');
const geminiService = require('../services/geminiService');
const { descriptionError } = require('../validators/vendorValidators');
const mongoose = require('mongoose');
const {
  listingError,
  titleError,
  stockChangeError,
  availabilityError,
  relistError,
} = require('../validators/listingValidators');
const SalesRecord = require('../models/SalesRecord');
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

// Relisted items count as newest from when they went back on sale.
const withListedAt = { $addFields: { _listedAt: { $ifNull: ['$listedAt', '$createdAt'] } } };
const NEWEST_FIRST = { _listedAt: -1, _id: -1 };

function availablePipeline({ now, stock, sort, skip = 0, limit }) {
  return [
    availableMatch(now, stock),
    withListedAt,
    { $sort: sort },
    ...withStall,
    { $skip: skip },
    { $limit: limit },
    publicFields,
  ];
}

const escapeRegex = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// A vendor can't have two listings with the same name; case and spacing don't count.
const SAME_NAME = 'SAME_NAME';
const sameNamePattern = (title) =>
  new RegExp(`^\\s*${title.trim().split(/\s+/).map(escapeRegex).join('\\s+')}\\s*$`, 'i');

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
    withListedAt,
    { $sort: { _score: -1, ...NEWEST_FIRST } },
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
      sort: NEWEST_FIRST,
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
  const sameName = await Listing.exists({ vendor: vendor._id, title: sameNamePattern(title) });
  if (sameName) {
    return res.status(409).json({
      code: SAME_NAME,
      listingId: String(sameName._id),
      error: `You already have a listing called ${title.trim()}.`,
    });
  }
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
  const listedTime = (item) => new Date(item.listedAt ?? item.createdAt ?? 0).getTime();
  listings.sort((a, b) => listedTime(b) - listedTime(a));
  return res.json({ listings });
}

const LISTING_NOT_FOUND = { code: 'LISTING_NOT_FOUND', error: 'Listing not found.' };
const PICKUP_OVER = { code: 'PICKUP_ENDED', error: 'Pickup has ended.' };
const EDITABLE_STATUSES = ['active', 'paused'];

// The vendor and their own listing, or null (after replying) when either is missing.
async function findOwnListing(req, res) {
  const vendor = await Vendor.findOne({ user: req.user._id });
  if (!vendor) {
    res.status(404).json(NO_PROFILE);
    return null;
  }
  const listing = mongoose.isValidObjectId(req.params.id)
    ? await Listing.findOne({ _id: req.params.id, vendor: vendor._id })
    : null;
  if (!listing) {
    res.status(404).json(LISTING_NOT_FOUND);
    return null;
  }
  return { listing, vendor };
}

// Items sold in earlier rounds of this listing.
async function pastSoldFor(listingId) {
  const [total] = await SalesRecord.aggregate([
    { $match: { listing: listingId } },
    { $group: { _id: null, sold: { $sum: '$sold' } } },
  ]);
  return total?.sold ?? 0;
}

async function getMineOne(req, res) {
  const found = await findOwnListing(req, res);
  if (!found) return undefined;
  return res.json({ listing: found.listing, pastSold: await pastSoldFor(found.listing._id) });
}

function stockChanged(expected, current) {
  const ordered = expected - current;
  const error = ordered > 0
    ? `${ordered} ${ordered === 1 ? 'item was' : 'items were'} ordered while you were editing. `
      + `Current available stock is now ${current}.`
    : `Current available stock changed to ${current} while you were editing.`;
  return { code: 'STOCK_CHANGED', current, error };
}

async function updateStock(req, res) {
  const invalid = stockChangeError(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const { listing } = (await findOwnListing(req, res)) ?? {};
  if (!listing) return undefined;

  const { quantity, expectedQuantity } = req.body;
  const now = new Date();
  // Set only if no order changed the stock since the vendor loaded it.
  const updated = await Listing.findOneAndUpdate(
    {
      _id: listing._id,
      status: { $in: EDITABLE_STATUSES },
      pickupEnd: { $gt: now },
      quantityAvailable: expectedQuantity,
    },
    { $set: { quantityAvailable: quantity } },
    { returnDocument: 'after' }
  );
  if (updated) return res.json({ listing: updated });

  const current = await Listing.findById(listing._id);
  if (!current) return res.status(404).json(LISTING_NOT_FOUND);
  if (current.pickupEnd <= now || !EDITABLE_STATUSES.includes(current.status)) {
    return res.status(409).json(PICKUP_OVER);
  }
  return res.status(409).json(stockChanged(expectedQuantity, current.quantityAvailable));
}

async function updateAvailability(req, res) {
  const invalid = availabilityError(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const { listing } = (await findOwnListing(req, res)) ?? {};
  if (!listing) return undefined;

  const updated = await Listing.findOneAndUpdate(
    { _id: listing._id, status: { $in: EDITABLE_STATUSES }, pickupEnd: { $gt: new Date() } },
    { $set: { status: req.body.paused ? 'paused' : 'active' } },
    { returnDocument: 'after' }
  );
  if (!updated) return res.status(409).json(PICKUP_OVER);
  return res.json({ listing: updated });
}

const PICKUP_STILL_OPEN = { code: 'PICKUP_NOT_ENDED', error: 'You can relist this once pickup has ended.' };
const ALREADY_RELISTED = { code: 'ALREADY_RELISTED', error: 'This item has already been relisted.' };

function salesRecordFrom(listing, vendor) {
  const sold = listing.soldCount ?? 0;
  const leftover = Math.max(listing.quantityAvailable, 0);
  return {
    listing: listing._id,
    vendor: vendor._id,
    stallName: vendor.stallName,
    pickupAddress: vendor.address,
    itemName: listing.title,
    category: listing.category,
    originalPrice: listing.originalPrice,
    discountedPrice: listing.discountedPrice,
    pickupStart: listing.pickupStart,
    pickupEnd: listing.pickupEnd,
    stockOffered: sold + leftover,
    sold,
    leftover,
  };
}

// Saves the finished round as a sales record, then puts the same listing back on sale.
async function relist(req, res) {
  const now = new Date();
  const invalid = relistError(req.body, now);
  if (invalid) return res.status(400).json({ error: invalid });

  const found = await findOwnListing(req, res);
  if (!found) return undefined;
  const { listing, vendor } = found;
  if (listing.pickupEnd > now) return res.status(409).json(PICKUP_STILL_OPEN);

  // Matching the old pickup end means two relists of the same round can't both succeed.
  const before = await Listing.findOneAndUpdate(
    { _id: listing._id, pickupEnd: listing.pickupEnd },
    {
      $set: {
        quantityAvailable: req.body.quantityAvailable,
        pickupStart: new Date(req.body.pickupStart),
        pickupEnd: new Date(req.body.pickupEnd),
        soldCount: 0,
        status: req.body.paused === true ? 'paused' : 'active',
        listedAt: now,
      },
    },
    { returnDocument: 'before' }
  );
  if (!before) return res.status(409).json(ALREADY_RELISTED);

  try {
    await SalesRecord.create(salesRecordFrom(before, vendor));
  } catch (err) {
    await Listing.updateOne(
      { _id: before._id, listedAt: now },
      {
        $set: {
          quantityAvailable: before.quantityAvailable,
          pickupStart: before.pickupStart,
          pickupEnd: before.pickupEnd,
          soldCount: before.soldCount,
          status: before.status,
          listedAt: before.listedAt ?? before.createdAt,
        },
      }
    );
    throw err;
  }

  const relisted = await Listing.findById(listing._id);
  return res.json({ listing: relisted, pastSold: await pastSoldFor(listing._id) });
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

module.exports = {
  createListing,
  getAvailable,
  getRunningOut,
  search,
  getDetails,
  getMine,
  getMineOne,
  updateStock,
  updateAvailability,
  relist,
  suggestAllergens,
};
