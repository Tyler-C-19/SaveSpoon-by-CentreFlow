const TOKEN_MAX_LENGTH = 4096;
const TOKEN_ERROR = 'The device token is missing or not valid.';

function isDeviceToken(value) {
  return typeof value === 'string' && value.trim().length > 0 && value.length <= TOKEN_MAX_LENGTH;
}

// Only the switches for the user's own role, each true or false.
function prefsError(prefs, allowed) {
  if (!prefs || typeof prefs !== 'object' || Array.isArray(prefs)) return 'Choose which notifications to get.';
  const keys = Object.keys(prefs);
  if (!keys.length) return 'Choose which notifications to get.';
  if (keys.some((key) => !allowed.includes(key))) return 'One of these notification settings is not available.';
  if (keys.some((key) => typeof prefs[key] !== 'boolean')) return 'Each notification setting must be on or off.';
  return null;
}

module.exports = { isDeviceToken, prefsError, TOKEN_ERROR };
