const mongoose = require('mongoose');
const Favourite = require('../models/Favourite');
const Listing = require('../models/Listing');

const { MAX_FAVOURITES } = Favourite;
const GONE = { code: 'LISTING_GONE', error: 'This item is no longer available.' };
const FULL = { code: 'FAVOURITES_FULL', error: `You can save up to ${MAX_FAVOURITES} Favourites.` };
const DUPLICATE_KEY = 11000;

async function getIds(req, res) {
  const found = await Favourite.find({ customer: req.user._id }).sort({ createdAt: -1, _id: -1 }).select('listing');
  return res.json({ listingIds: found.map((item) => String(item.listing)) });
}

async function add(req, res) {
  const { listingId } = req.params;
  if (!mongoose.isValidObjectId(listingId) || !(await Listing.exists({ _id: listingId }))) {
    return res.status(404).json(GONE);
  }
  const customer = req.user._id;
  if (await Favourite.exists({ customer, listing: listingId })) {
    return res.json({ listingId, favourite: true });
  }
  if ((await Favourite.countDocuments({ customer })) >= MAX_FAVOURITES) {
    return res.status(409).json(FULL);
  }
  try {
    await Favourite.create({ customer, listing: listingId });
  } catch (err) {
    // Two taps at once: the first one saved it.
    if (err.code !== DUPLICATE_KEY) throw err;
  }
  return res.json({ listingId, favourite: true });
}

async function remove(req, res) {
  const { listingId } = req.params;
  if (mongoose.isValidObjectId(listingId)) {
    await Favourite.deleteOne({ customer: req.user._id, listing: listingId });
  }
  return res.json({ listingId, favourite: false });
}

module.exports = { getIds, add, remove };
