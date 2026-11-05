const crypto = require('crypto');
const bcrypt = require('bcryptjs');

const OTP_LIFETIME_MS = 5 * 60 * 1000;
const RESEND_COOLDOWN_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;

function generateCode() {
  return crypto.randomInt(0, 1000000).toString().padStart(6, '0');
}

// Sent time = expiry - lifetime.
function canSendNewCode(user, now = Date.now()) {
  if (!user.otpExpiresAt) return true;
  const sentAt = user.otpExpiresAt.getTime() - OTP_LIFETIME_MS;
  return now - sentAt >= RESEND_COOLDOWN_MS;
}

async function issueCode(user, purpose, now = Date.now()) {
  const code = generateCode();
  user.otpHash = await bcrypt.hash(code, 10);
  user.otpPurpose = purpose;
  user.otpExpiresAt = new Date(now + OTP_LIFETIME_MS);
  user.otpAttempts = 0;
  return code;
}

function clearCode(user) {
  user.otpHash = undefined;
  user.otpPurpose = undefined;
  user.otpExpiresAt = undefined;
  user.otpAttempts = 0;
}

async function checkCode(user, purpose, code, now = Date.now()) {
  if (!user.otpHash || user.otpPurpose !== purpose) return false;
  if (!user.otpExpiresAt || user.otpExpiresAt.getTime() <= now) return false;
  if (user.otpAttempts >= MAX_ATTEMPTS) return false;
  user.otpAttempts += 1;
  return bcrypt.compare(code, user.otpHash);
}

module.exports = {
  OTP_LIFETIME_MS, RESEND_COOLDOWN_MS, MAX_ATTEMPTS, generateCode, canSendNewCode, issueCode, clearCode, checkCode,
};
