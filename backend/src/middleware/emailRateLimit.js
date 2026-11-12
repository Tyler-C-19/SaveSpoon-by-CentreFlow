const LIMIT = 30;
const WINDOW_MS = 60 * 60 * 1000;
const MAX_TRACKED = 10000;
const LOCAL = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);

// Counts requests per IP address. Requests from this computer are not counted.
function createEmailRateLimit({ limit = LIMIT, windowMs = WINDOW_MS, now = Date.now } = {}) {
  const usage = new Map();

  return function emailRateLimit(req, res, next) {
    if (LOCAL.has(req.ip)) return next();

    const time = now();
    if (usage.size > MAX_TRACKED) {
      for (const [key, entry] of usage) {
        if (entry.resetAt <= time) usage.delete(key);
      }
    }

    let entry = usage.get(req.ip);
    if (!entry || entry.resetAt <= time) {
      entry = { count: 0, resetAt: time + windowMs };
      usage.set(req.ip, entry);
    }

    if (entry.count >= limit) {
      const waitMs = entry.resetAt - time;
      res.set('Retry-After', String(Math.ceil(waitMs / 1000)));
      return res.status(429).json({
        error: `Too many requests from this network. Try again in ${Math.ceil(waitMs / 60000)} min.`,
      });
    }

    entry.count += 1;
    return next();
  };
}

const emailRateLimit = createEmailRateLimit();

module.exports = { createEmailRateLimit, emailRateLimit, EMAIL_LIMIT: LIMIT };
