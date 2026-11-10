const { isText, PHONE_PATTERN, passwordError } = require('./authValidators');

function detailsError(body = {}) {
  const { name, phone } = body;
  if (name === undefined && phone === undefined) return 'Nothing to update.';
  if (name !== undefined && (!isText(name) || !name.trim() || name.trim().length > 100)) {
    return 'Enter your full name.';
  }
  if (phone !== undefined && (!isText(phone) || !PHONE_PATTERN.test(phone.trim()))) {
    return 'Enter a valid phone number.';
  }
  return null;
}

function newPasswordError(currentPassword, newPassword) {
  if (!isText(currentPassword) || !currentPassword) return 'Enter your current password.';
  return passwordError(newPassword);
}

function cropError(crop) {
  const values = ['x', 'y', 'width', 'height'].map((key) => crop?.[key]);
  if (!values.every((value) => Number.isFinite(value) && value >= 0 && value <= 1)) {
    return 'Adjust your profile picture again.';
  }
  const [x, y, width, height] = values;
  const slack = 0.001;
  if (width < 0.01 || height < 0.01 || x + width > 1 + slack || y + height > 1 + slack) {
    return 'Adjust your profile picture again.';
  }
  return null;
}

module.exports = { detailsError, newPasswordError, cropError };
