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
  if (!user) {
    return res.status(401).json({ error: 'Your session has expired. Log in again.' });
  }

  req.user = user;
  return next();
}

module.exports = { requireAuth };
