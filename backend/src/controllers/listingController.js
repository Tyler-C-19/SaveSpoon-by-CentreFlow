const Listing = require('../models/Listing');
const Vendor = require('../models/Vendor');
const User = require('../models/User');
const { findLiveListing, unavailableProblem, GONE, LISTING_GONE } = require('../services/orderService');
const geminiService = require('../services/geminiService');
const { descriptionError } = require('../validators/vendorValidators');
const mongoose = require('mongoose');
const {
  listingError,
  listingEditError,
  titleError,
  stockChangeError,
  availabilityError,
  relistError,
} = require('../validators/listingValidators');
const SalesRecord = require('../models/SalesRecord');
const Favourite = require('../models/Favourite');
const { parseFilters, filterMatch } = require('../validators/searchFilters');
const { createUsageLimiter } = require('../services/usageLimiter');
const { normaliseAllergens, LOW_STOCK_LIMIT } = require('../models/listingOptions');
const { NO_PROFILE } = require('./vendorController');
const { countActiveOrders } = require('../services/accountService');
const notifications = require('../services/notificationService');
const listingPhotos = require('../services/listingPhotoService');

const suggestionLimiter = createUsageLimiter({ limit: 10, windowMs: 60 * 60 * 1000 });

const PAGE_SIZE = 20;
const RUNNING_OUT_SIZE = 6;
const OTHER_STALLS_SIZE = 6;
const OTHER_LISTINGS_SIZE = 4;
const FAVOURITES_STRIP_SIZE = 6;
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
    imageThumbUrl: 1,
    status: 1,
    createdAt: 1,
    stallName: '$vendorProfile.stallName',
  },
};

// Relisted items count as newest from when they went back on sale.
const withListedAt = { $addFields: { _listedAt: { $ifNull: ['$listedAt', '$createdAt'] } } };
const NEWEST_FIRST = { _listedAt: -1, _id: -1 };

// Share of the original price saved; 0 when there is no original price.
const withSaving = {
  $addFields: {
    _saving: {
      $cond: [
        { $gt: ['$originalPrice', 0] },
        { $divide: [{ $subtract: ['$originalPrice', '$discountedPrice'] }, '$originalPrice'] },
        0,
      ],
    },
  },
};

const SORT_ORDERS = {
  best: { _score: -1, ...NEWEST_FIRST },
  newest: NEWEST_FIRST,
  price_asc: { discountedPrice: 1, ...NEWEST_FIRST },
  price_desc: { discountedPrice: -1, ...NEWEST_FIRST },
  ending: { pickupEnd: 1, ...NEWEST_FIRST },
  sold: { soldCount: -1, ...NEWEST_FIRST },
  saving: { _saving: -1, ...NEWEST_FIRST },
};

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

function searchStages(now, { text, words }, extraMatch = {}) {
  const wordFields = Object.fromEntries(words.map((word, index) => [`_word${index}`, wordScore(word)]));
  const wordKeys = words.map((_, index) => `$_word${index}`);
  return [
    { $match: { ...availableMatch(now).$match, ...extraMatch } },
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
  const filters = parseFilters(req.query);
  if (filters.error) return res.status(400).json({ error: filters.error });

  // The keyword is optional once a filter or sort is chosen.
  const hasKeyword = q !== undefined;
  if (hasKeyword || (!filters.filtered && !filters.sort)) {
    const length = typeof q === 'string' ? q.trim().replace(/\s+/g, ' ').length : 0;
    if (length < 1 || length > SEARCH_MAX_LENGTH) {
      return res.status(400).json({ error: `Enter 1 to ${SEARCH_MAX_LENGTH} characters to search.` });
    }
  }
  if (filters.sort === 'best' && !hasKeyword) {
    return res.status(400).json({ error: 'Best Match needs a keyword.' });
  }

  const now = new Date();
  const match = filterMatch(filters, now);
  if (filters.favourites) {
    match._id = { $in: await Favourite.distinct('listing', { customer: req.user._id }) };
  }
  const sort = filters.sort ?? (hasKeyword ? 'best' : 'newest');
  const words = hasKeyword ? searchWords(q) : null;
  const found = await Listing.aggregate([
    ...(words ? searchStages(now, words, match) : [{ $match: { ...availableMatch(now).$match, ...match } }, ...withStall]),
    withListedAt,
    ...(sort === 'saving' ? [withSaving] : []),
    { $sort: SORT_ORDERS[sort] },
    { $skip: (Number(page) - 1) * PAGE_SIZE },
    { $limit: PAGE_SIZE + 1 },
    searchFields,
  ]);
  const listings = found.slice(0, PAGE_SIZE);
  const body = { listings, hasMore: found.length > PAGE_SIZE };
  if (page === '1') {
    const plain = words && !filters.filtered && sort === 'best';
    body.otherStalls = plain ? await otherStalls(now, words, listings) : [];
  }
  return res.json(body);
}

// The customer's Favourites that are on sale now, most recently added first.
async function getFavourites(req, res) {
  const saved = await Favourite.find({ customer: req.user._id }).sort({ createdAt: -1, _id: -1 }).select('listing');
  const ids = saved.map((item) => item.listing);
  if (!ids.length) return res.json({ listings: [], hasMore: false });

  const found = await Listing.aggregate([
    { $match: { ...availableMatch(new Date()).$match, _id: { $in: ids } } },
    ...withStall,
    publicFields,
  ]);
  const position = new Map(ids.map((id, index) => [String(id), index]));
  found.sort((a, b) => position.get(String(a._id)) - position.get(String(b._id)));
  return res.json({
    listings: found.slice(0, FAVOURITES_STRIP_SIZE),
    hasMore: found.length > FAVOURITES_STRIP_SIZE,
  });
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

  const {
    vendor: vendorId, location, imageId, imageOriginalUrl, imageWidth, imageHeight, imageCrop, ...details
  } = listing.toObject();
  return res.json({
    listing: {
      ...details,
      stallName: vendor.stallName,
      pickupAddress: vendor.address,
      pickupLocation: vendor.location?.coordinates,
      pickupPlaceId: vendor.placeId,
      vendorPhone: vendor.phone,
    },
  });
}

async function getVendorInfo(req, res) {
  const { listing, vendor } = await findLiveListing(req.params.id);
  if (!listing || unavailableProblem(listing)?.code === LISTING_GONE) {
    const { status, ...problem } = GONE;
    return res.status(status).json(problem);
  }

  const [owner, otherListings] = await Promise.all([
    User.findById(vendor.user, 'photoUrl'),
    Listing.aggregate([
      availableMatch(new Date()),
      { $match: { vendor: vendor._id, _id: { $ne: listing._id } } },
      withListedAt,
      { $sort: { soldCount: -1, ...NEWEST_FIRST } },
      { $limit: OTHER_LISTINGS_SIZE },
      ...withStall,
      publicFields,
    ]),
  ]);
  return res.json({
    vendor: {
      stallName: vendor.stallName,
      description: vendor.description,
      address: vendor.address,
      phone: vendor.phone,
      photoUrl: owner?.photoUrl,
      location: vendor.location?.coordinates,
      placeId: vendor.placeId,
    },
    otherListings,
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
  const [pastSold, activeOrderCount] = await Promise.all([
    pastSoldFor(found.listing._id),
    countActiveOrders({ listing: found.listing._id }),
  ]);
  return res.json({ listing: found.listing, pastSold, activeOrderCount });
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

  const { listing, vendor } = (await findOwnListing(req, res)) ?? {};
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
  if (updated) {
    if (listing.quantityAvailable <= 0) {
      notifications.inBackground(() => notifications.favouriteBack(updated, vendor, 'back_in_stock'));
    }
    return res.json({ listing: updated });
  }

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

  const { listing, vendor } = (await findOwnListing(req, res)) ?? {};
  if (!listing) return undefined;

  const updated = await Listing.findOneAndUpdate(
    { _id: listing._id, status: { $in: EDITABLE_STATUSES }, pickupEnd: { $gt: new Date() } },
    { $set: { status: req.body.paused ? 'paused' : 'active' } },
    { returnDocument: 'after' }
  );
  if (!updated) return res.status(409).json(PICKUP_OVER);
  if (listing.status === 'paused' && updated.status === 'active') {
    notifications.inBackground(() => notifications.favouriteBack(updated, vendor, 'relisted'));
  }
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
  if (relisted) notifications.inBackground(() => notifications.favouriteBack(relisted, vendor, 'relisted'));
  return res.json({ listing: relisted, pastSold: await pastSoldFor(listing._id) });
}

const PICKUP_LOCKED = { code: 'PICKUP_LOCKED', error: "Pickup time can't change while you have active orders." };
const sameTime = (a, b) => new Date(a).getTime() === new Date(b).getTime();

async function updateListing(req, res) {
  const found = await findOwnListing(req, res);
  if (!found) return undefined;
  const { listing, vendor } = found;
  const now = new Date();
  if (listing.pickupEnd <= now || !EDITABLE_STATUSES.includes(listing.status)) {
    return res.status(409).json(PICKUP_OVER);
  }

  const invalid = listingEditError(req.body, now);
  if (invalid) return res.status(400).json({ error: invalid });

  const { title, description, category, isHalal, originalPrice, discountedPrice } = req.body;
  const sameName = await Listing.exists({
    _id: { $ne: listing._id },
    vendor: vendor._id,
    title: sameNamePattern(title),
  });
  if (sameName) {
    return res.status(409).json({
      code: SAME_NAME,
      listingId: String(sameName._id),
      error: `You already have a listing called ${title.trim()}.`,
    });
  }

  const pickupStart = new Date(req.body.pickupStart);
  const pickupEnd = new Date(req.body.pickupEnd);
  const windowChanged = !sameTime(pickupStart, listing.pickupStart) || !sameTime(pickupEnd, listing.pickupEnd);
  if (windowChanged && (await countActiveOrders({ listing: listing._id }))) {
    return res.status(409).json(PICKUP_LOCKED);
  }

  const changes = {
    title: title.trim(),
    category,
    isHalal,
    originalPrice,
    discountedPrice,
    pickupStart,
    pickupEnd,
    ...normaliseAllergens(req.body.allergens, req.body.otherAllergens),
  };
  const text = description?.trim();
  if (text) changes.description = text;
  const update = text ? { $set: changes } : { $set: changes, $unset: { description: '' } };

  // Stock is only touched when the vendor changed it, and only if no order changed it meanwhile.
  const { quantityAvailable, expectedQuantity } = req.body;
  const filter = { _id: listing._id, status: { $in: EDITABLE_STATUSES }, pickupEnd: { $gt: now } };
  if (quantityAvailable !== expectedQuantity) {
    filter.quantityAvailable = expectedQuantity;
    changes.quantityAvailable = quantityAvailable;
  }

  const updated = await Listing.findOneAndUpdate(filter, update, { returnDocument: 'after' });
  if (updated) {
    notifications.inBackground(() => notifications.itemChanged(listing, updated, vendor));
    if (listing.quantityAvailable <= 0 && updated.quantityAvailable > 0) {
      notifications.inBackground(() => notifications.favouriteBack(updated, vendor, 'back_in_stock'));
    }
    return res.json({ listing: updated });
  }

  const current = await Listing.findById(listing._id);
  if (!current) return res.status(404).json(LISTING_NOT_FOUND);
  if (current.pickupEnd <= now || !EDITABLE_STATUSES.includes(current.status)) {
    return res.status(409).json(PICKUP_OVER);
  }
  return res.status(409).json(stockChanged(expectedQuantity, current.quantityAvailable));
}

// The current round up to now, kept when the listing is deleted.
function deletionRecordFrom(listing, vendor, now) {
  const record = salesRecordFrom(listing, vendor);
  const pickupEnd = listing.pickupEnd < now ? listing.pickupEnd : now;
  return {
    ...record,
    pickupStart: listing.pickupStart < pickupEnd ? listing.pickupStart : pickupEnd,
    pickupEnd,
    reason: 'deleted',
  };
}

async function deleteListing(req, res) {
  const found = await findOwnListing(req, res);
  if (!found) return undefined;
  const { listing, vendor } = found;

  const activeOrderCount = await countActiveOrders({ listing: listing._id });
  if (activeOrderCount) {
    const orders = activeOrderCount === 1 ? '1 active order' : `${activeOrderCount} active orders`;
    return res.status(409).json({
      code: 'ACTIVE_ORDERS',
      activeOrderCount,
      pickupEnd: listing.pickupEnd,
      error: `You have ${orders} for this item. You can delete it once pickup ends.`,
    });
  }

  const record = deletionRecordFrom(listing, vendor, new Date());
  const saved = record.stockOffered > 0 ? await SalesRecord.create(record) : null;
  const undoRecord = () => (saved ? SalesRecord.deleteOne({ _id: saved._id }) : null);

  let result;
  try {
    result = await Listing.deleteOne({ _id: listing._id, vendor: vendor._id });
  } catch (err) {
    await undoRecord();
    throw err;
  }
  if (!result.deletedCount) {
    await undoRecord();
    return res.status(404).json(LISTING_NOT_FOUND);
  }
  await Favourite.deleteMany({ listing: listing._id });
  await listingPhotos.removeQuietly(listing.imageId);
  return res.json({ deleted: true, listingId: String(listing._id) });
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
  getFavourites,
  search,
  getDetails,
  getVendorInfo,
  getMine,
  getMineOne,
  updateStock,
  updateAvailability,
  relist,
  updateListing,
  deleteListing,
  suggestAllergens,
  findOwnListing,
  EDITABLE_STATUSES,
  PICKUP_OVER,
};
