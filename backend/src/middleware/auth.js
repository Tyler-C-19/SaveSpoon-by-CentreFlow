const User = require('../models/User');
const { verifyToken } = require('../services/tokenService');

async function requireAuth(req, res, next) {
  const [scheme, token] = (req.headers.authorization || '').split(' ');
  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'Log in to continue.' });
  }

  let payload;
  try {
    payload = verifyToken(token);
  } catch {
    return res.status(401).json({ error: 'Your session has expired. Log in again.' });
  }

  const user = await User.findById(payload.sub);
  const changedAt = user?.passwordChangedAt ? Math.floor(user.passwordChangedAt.getTime() / 1000) : 0;
  if (!user || payload.iat < changedAt) {
    return res.status(401).json({ error: 'Your session has expired. Log in again.' });
  }

  req.user = user;
  return next();
}

function requireRole(...roles) {
  return [
    requireAuth,
    (req, res, next) => {
      if (!roles.includes(req.user.role)) {
        return res.status(403).json({ error: "You don't have access to this." });
      }
      return next();
    },
  ];
}

module.exports = { requireAuth, requireRole };
