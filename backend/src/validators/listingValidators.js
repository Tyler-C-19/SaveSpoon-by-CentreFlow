const { isText } = require('./authValidators');
const { descriptionError } = require('./vendorValidators');
const {
  CATEGORIES,
  ALLERGENS,
  OTHER_ALLERGEN_PATTERN,
  MAX_OTHER_ALLERGENS,
} = require('../models/listingOptions');

const DAY_MS = 24 * 60 * 60 * 1000;

const isMoney = (value) =>
  Number.isFinite(value) && value > 0 && Math.abs(value * 100 - Math.round(value * 100)) < 1e-6;

const titleError = (title) =>
  !isText(title) || title.trim().length < 2 || title.trim().length > 80
    ? 'Item name must be 2 to 80 characters.'
    : null;

function pickupError(pickupStart, pickupEnd, now) {
  const start = isText(pickupStart) ? new Date(pickupStart) : null;
  const end = isText(pickupEnd) ? new Date(pickupEnd) : null;
  if (!start || !end || Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
    return 'Choose a pickup start and end time.';
  }
  if (end <= start) return 'Pickup must end after it starts.';
  if (end <= now) return 'Pickup must end in the future.';
  if (end.getTime() - now.getTime() > DAY_MS) return 'Pickup must end within 24 hours.';
  return null;
}

function allergensError(allergens) {
  if (allergens === undefined) return null;
  if (!Array.isArray(allergens) || !allergens.every((item) => ALLERGENS.includes(item))) {
    return 'Choose allergens from the list.';
  }
  return null;
}

function otherAllergensError(otherAllergens) {
  if (otherAllergens === undefined) return null;
  if (
    !Array.isArray(otherAllergens)
    || otherAllergens.length > MAX_OTHER_ALLERGENS
    || !otherAllergens.every((item) => isText(item) && OTHER_ALLERGEN_PATTERN.test(item.trim()))
  ) {
    return 'Other allergens must be up to 5 names of 2 to 40 letters each.';
  }
  return null;
}

// Keep in sync with mobile listing_validators.dart.
function listingError(body = {}, now = new Date()) {
  const { title, description, category, isHalal, originalPrice, discountedPrice, quantityAvailable } = body;
  const invalidTitle = titleError(title);
  if (invalidTitle) return invalidTitle;
  const invalidDescription = descriptionError(description);
  if (invalidDescription) return invalidDescription;
  if (!CATEGORIES.includes(category)) return 'Choose a category.';
  if (typeof isHalal !== 'boolean') return 'Say whether this food is halal.';
  if (!isMoney(originalPrice)) return 'Enter an original price above 0, with up to 2 decimal places.';
  if (!isMoney(discountedPrice)) return 'Enter a discounted price above 0, with up to 2 decimal places.';
  if (discountedPrice >= originalPrice) return 'Discounted price must be less than the original price.';
  if (!Number.isInteger(quantityAvailable) || quantityAvailable < 1 || quantityAvailable > 999) {
    return 'Stock must be a whole number from 1 to 999.';
  }
  return pickupError(body.pickupStart, body.pickupEnd, now)
    || allergensError(body.allergens)
    || otherAllergensError(body.otherAllergens);
}

module.exports = { listingError, titleError };
