function createUsageLimiter({ limit, windowMs, now = Date.now }) {
  const usage = new Map();

  function take(key) {
    const time = now();
    for (const [id, entry] of usage) {
      if (entry.resetAt <= time) usage.delete(id);
    }

    const entry = usage.get(key) ?? { count: 0, resetAt: time + windowMs };
    if (entry.count >= limit) return { allowed: false, retryAfterMs: entry.resetAt - time };

    entry.count += 1;
    usage.set(key, entry);
    return { allowed: true, retryAfterMs: 0 };
  }

  return { take };
}

module.exports = { createUsageLimiter };
