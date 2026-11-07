const { PHONE_PATTERN, isText } = require('./authValidators');

const PLACE_ID_PATTERN = /^[\w-]{1,512}$/;

const inRange = (value, min, max) => Number.isFinite(value) && value >= min && value <= max;

function descriptionError(description) {
  if (description === undefined || description === null) return null;
  if (!isText(description) || description.trim().length > 500) {
    return 'Description must be 500 characters or fewer.';
  }
  return null;
}

function locationError(location) {
  const coordinates = location?.coordinates;
  if (
    location?.type !== 'Point'
    || !Array.isArray(coordinates)
    || coordinates.length !== 2
    || !inRange(coordinates[0], -180, 180)
    || !inRange(coordinates[1], -90, 90)
  ) {
    return 'Place a pin on the map.';
  }
  return null;
}

// Keep in sync with mobile vendor_validators.dart.
function vendorProfileError(body = {}) {
  const { stallName, phone, address, description, location, placeId } = body;
  if (placeId !== undefined && (!isText(placeId) || !PLACE_ID_PATTERN.test(placeId))) {
    return 'That place could not be found.';
  }
  if (!isText(stallName) || stallName.trim().length < 2 || stallName.trim().length > 80) {
    return 'Business name must be 2 to 80 characters.';
  }
  if (!isText(phone) || !PHONE_PATTERN.test(phone.trim())) return 'Enter a valid phone number.';
  if (!isText(address) || !address.trim() || address.trim().length > 200) {
    return 'Enter a pickup address of up to 200 characters.';
  }
  return descriptionError(description) || locationError(location);
}

module.exports = { vendorProfileError, descriptionError };
