const jwt = require('jsonwebtoken');

const TOKEN_LIFETIME = '7d';

function signToken(userId) {
  return jwt.sign({}, process.env.JWT_SECRET, {
    subject: String(userId),
    expiresIn: TOKEN_LIFETIME,
    algorithm: 'HS256',
  });
}

function verifyToken(token) {
  return jwt.verify(token, process.env.JWT_SECRET, { algorithms: ['HS256'] });
}

module.exports = { signToken, verifyToken };
