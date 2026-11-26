// Sends phone notifications through Firebase Cloud Messaging.
const KEYS = ['FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY'];
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);
// FCM takes up to 500 tokens per call.
const BATCH_SIZE = 500;

let messaging;
let checked = false;

function isConfigured() {
  return KEYS.every((key) => process.env[key]);
}

// Accepts the key on one line with \n for each line break, or with real line
// breaks, and drops quotes pasted around it.
function privateKey(value) {
  return value.replace(/^\s*(['"])([\s\S]*)\1\s*$/, '$2').replace(/\\n/g, '\n');
}

function getMessaging() {
  if (checked) return messaging;
  checked = true;
  if (!isConfigured()) {
    console.log('Push notifications are off: the Firebase settings are missing.');
    return null;
  }
  const { initializeApp, cert } = require('firebase-admin/app');
  const { getMessaging: messagingFor } = require('firebase-admin/messaging');
  const app = initializeApp({
    credential: cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: privateKey(process.env.FIREBASE_PRIVATE_KEY),
    }),
  });
  messaging = messagingFor(app);
  return messaging;
}

function messageFor({ title, body, data = {}, channel = 'orders', silent = false }) {
  const strings = Object.fromEntries(
    Object.entries(data).filter(([, value]) => value != null).map(([key, value]) => [key, String(value)])
  );
  if (silent) return { data: strings, android: { priority: 'high' } };
  return {
    notification: { title, body },
    data: strings,
    android: {
      priority: 'high',
      notification: { channelId: channel, icon: 'ic_stat_savespoon', color: '#1B8A3A' },
    },
  };
}

// Returns the tokens FCM says no longer work, so they can be removed.
async function sendToTokens(tokens, message) {
  const sender = getMessaging();
  if (!sender || !tokens.length) return [];
  const dead = [];
  for (let start = 0; start < tokens.length; start += BATCH_SIZE) {
    const batch = tokens.slice(start, start + BATCH_SIZE);
    const result = await sender.sendEachForMulticast({ tokens: batch, ...messageFor(message) });
    result.responses.forEach((response, index) => {
      if (!response.success && DEAD_TOKEN_CODES.has(response.error?.code)) dead.push(batch[index]);
    });
  }
  return dead;
}

module.exports = { isConfigured, sendToTokens, messageFor, privateKey };
