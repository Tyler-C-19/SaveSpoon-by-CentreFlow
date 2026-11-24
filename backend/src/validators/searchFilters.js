const { CATEGORIES, ALLERGENS } = require('../models/listingOptions');

const SORTS = ['best', 'newest', 'price_asc', 'price_desc', 'ending', 'sold', 'saving'];
const MAX_PRICE_LIMIT = 999;
const PRICE_PATTERN = /^\d{1,3}(\.\d{1,2})?$/;
const FILTER_KEYS = ['category', 'halal', 'maxPrice', 'avoid', 'favourites', 'openNow'];

const invalid = (error) => ({ error });

// A comma list where every item must be one of the allowed values.
function listOf(raw, allowed, label) {
  if (raw === undefined) return { values: [] };
  if (typeof raw !== 'string') return invalid(`Choose a valid ${label}.`);
  const values = [...new Set(raw.split(',').map((item) => item.trim()).filter(Boolean))];
  if (!values.length || values.some((item) => !allowed.includes(item))) return invalid(`Choose a valid ${label}.`);
  return { values };
}

function flag(raw, label) {
  if (raw === undefined) return { on: false };
  if (raw !== '1') return invalid(`${label} must be 1.`);
  return { on: true };
}

// Reads the filter and sort settings from the query. Returns { error } or the settings.
function parseFilters(query) {
  const category = listOf(query.category, CATEGORIES, 'category');
  if (category.error) return category;
  const avoid = listOf(query.avoid, ALLERGENS, 'allergen');
  if (avoid.error) return avoid;
  const halal = flag(query.halal, 'Halal Only');
  if (halal.error) return halal;
  const favourites = flag(query.favourites, 'Favourites');
  if (favourites.error) return favourites;
  const openNow = flag(query.openNow, 'Pickup Open Now');
  if (openNow.error) return openNow;

  let maxPrice = null;
  if (query.maxPrice !== undefined) {
    if (typeof query.maxPrice !== 'string' || !PRICE_PATTERN.test(query.maxPrice)) {
      return invalid('Choose a valid max price.');
    }
    maxPrice = Number(query.maxPrice);
    if (maxPrice > MAX_PRICE_LIMIT) return invalid('Choose a valid max price.');
  }

  let sort = null;
  if (query.sort !== undefined) {
    if (typeof query.sort !== 'string' || !SORTS.includes(query.sort)) return invalid('Choose a valid sort.');
    sort = query.sort;
  }

  return {
    categories: category.values,
    avoid: avoid.values,
    halal: halal.on,
    favourites: favourites.on,
    openNow: openNow.on,
    maxPrice,
    sort,
    filtered: FILTER_KEYS.some((key) => query[key] !== undefined),
  };
}

// The extra listing conditions for the chosen filters (favourites are added by the caller).
function filterMatch(filters, now) {
  const match = {};
  if (filters.categories.length) match.category = { $in: filters.categories };
  if (filters.halal) match.isHalal = true;
  if (filters.maxPrice !== null) match.discountedPrice = { $lte: filters.maxPrice };
  if (filters.avoid.length) match.allergens = { $nin: filters.avoid };
  if (filters.openNow) match.pickupStart = { $lte: now };
  return match;
}

module.exports = { parseFilters, filterMatch, SORTS, MAX_PRICE_LIMIT };
