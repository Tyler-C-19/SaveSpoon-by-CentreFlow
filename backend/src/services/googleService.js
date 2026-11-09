const { OAuth2Client } = require('google-auth-library');

let client;

async function verifyGoogleToken(idToken) {
  if (!client) client = new OAuth2Client();
  const ticket = await client.verifyIdToken({
    idToken,
    audience: process.env.GOOGLE_CLIENT_ID,
  });
  const payload = ticket.getPayload();
  return {
    googleId: payload.sub,
    email: payload.email,
    name: payload.name,
    emailVerified: payload.email_verified === true,
  };
}

module.exports = { verifyGoogleToken };
