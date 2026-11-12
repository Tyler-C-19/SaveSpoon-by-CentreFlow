const bcrypt = require('bcryptjs');

const MAX_WRONG_TRIES = 3;
const LOCK_MS = 15 * 60 * 1000;

const GUARD_FIELDS = '+passwordHash +passwordAttempts +passwordLockedUntil';

function lockedResult(user, now) {
  const minutes = Math.max(1, Math.ceil((user.passwordLockedUntil.getTime() - now) / 60000));
  return {
    status: 429,
    body: {
      error: `Too many wrong tries. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.`,
      code: 'TOO_MANY_TRIES',
    },
  };
}

// Shared by password change, email change and account deletion.
// Returns null when the password is right, otherwise the response to send.
async function checkPassword(user, password, now = Date.now()) {
  if (user.passwordLockedUntil && user.passwordLockedUntil.getTime() > now) {
    return lockedResult(user, now);
  }

  if (await bcrypt.compare(password, user.passwordHash)) {
    if (user.passwordAttempts || user.passwordLockedUntil) {
      user.passwordAttempts = 0;
      user.passwordLockedUntil = undefined;
      await user.save();
    }
    return null;
  }

  const attempts = (user.passwordAttempts || 0) + 1;
  if (attempts >= MAX_WRONG_TRIES) {
    user.passwordAttempts = 0;
    user.passwordLockedUntil = new Date(now + LOCK_MS);
    await user.save();
    return lockedResult(user, now);
  }

  user.passwordAttempts = attempts;
  await user.save();
  const left = MAX_WRONG_TRIES - attempts;
  return {
    status: 400,
    body: {
      error: `Your password is incorrect. ${left} ${left === 1 ? 'try' : 'tries'} left.`,
      code: 'WRONG_PASSWORD',
    },
  };
}

module.exports = { checkPassword, GUARD_FIELDS, MAX_WRONG_TRIES, LOCK_MS };
