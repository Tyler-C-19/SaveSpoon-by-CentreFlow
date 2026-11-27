const { CATEGORIES, ALLERGENS } = require('../models/listingOptions');

const SORTS = ['best', 'newest', 'price_asc', 'price_desc', 'ending', 'sold', 'saving', 'nearest'];
const MAX_PRICE_LIMIT = 999;
const PRICE_PATTERN = /^\d{1,3}(\.\d{1,2})?$/;
const FILTER_KEYS = ['category', 'halal', 'maxPrice', 'avoid', 'favourites', 'openNow'];
const COORDINATE_PATTERN = /^-?\d{1,3}(\.\d{1,6})?$/;
// About 110 m, so the exact spot isn't used.
const roundCoordinate = (value) => Math.round(value * 1000) / 1000;

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

// The customer's location for the Nearest sort, as [lng, lat]. Only used for this request.
function nearPoint(query) {
  if (query.lat === undefined && query.lng === undefined) return { point: null };
  const valid = [query.lat, query.lng].every((value) => typeof value === 'string' && COORDINATE_PATTERN.test(value));
  const lat = Number(query.lat);
  const lng = Number(query.lng);
  if (!valid || Math.abs(lat) > 90 || Math.abs(lng) > 180) return invalid('Your location is not valid.');
  return { point: [roundCoordinate(lng), roundCoordinate(lat)] };
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

  const near = nearPoint(query);
  if (near.error) return near;
  if (sort === 'nearest' && !near.point) return invalid('Nearest needs your location.');

  return {
    categories: category.values,
    avoid: avoid.values,
    halal: halal.on,
    favourites: favourites.on,
    openNow: openNow.on,
    maxPrice,
    sort,
    near: near.point,
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

// Straight-line metres from [point] to each listing's pickup pin. Close enough for sorting on one campus.
function withDistance([lng, lat]) {
  const metresPerDegree = 111320;
  const lngScale = Math.cos((lat * Math.PI) / 180);
  const offset = (index, origin, scale) => ({
    $multiply: [{ $subtract: [{ $arrayElemAt: ['$location.coordinates', index] }, origin] }, scale * metresPerDegree],
  });
  return {
    $addFields: {
      _distance: {
        $sqrt: {
          $add: [
            { $pow: [offset(0, lng, lngScale), 2] },
            { $pow: [offset(1, lat, 1), 2] },
          ],
        },
      },
    },
  };
}

module.exports = { parseFilters, filterMatch, withDistance, SORTS, MAX_PRICE_LIMIT };
