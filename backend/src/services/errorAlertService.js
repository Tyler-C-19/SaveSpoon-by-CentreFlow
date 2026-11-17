const emailService = require('./emailService');

const WINDOW_MS = 60 * 60 * 1000;
const MAX_TRACKED = 500;
const STACK_LINES = 5;
const MESSAGE_LENGTH = 300;

// The route pattern, such as /api/listings/:id, so no IDs or search text are included.
function routeOf(req) {
  if (!req.route) return '(no matching route)';
  return `${req.baseUrl || ''}${req.route.path}`;
}

function buildAlert(err, req, status, time) {
  const route = `${req.method} ${routeOf(req)}`;
  const name = err?.name || 'Error';
  const message = String(err?.message || '').slice(0, MESSAGE_LENGTH);
  const stack = String(err?.stack || '').split('\n').slice(1, STACK_LINES + 1).map((line) => line.trim());
  const when = new Date(time).toLocaleString('en-GB', { timeZone: 'Asia/Kuala_Lumpur' });

  return {
    subject: `SaveSpoon server error: ${status} on ${route}`,
    text: [
      `Time: ${when} (MYT)`,
      `Request: ${route}`,
      `Status: ${status}`,
      `Error: ${name}: ${message}`,
      'Trace:',
      ...stack.map((line) => `  ${line}`),
      '',
      'The same error on the same route is not emailed again for 1 hour.',
    ].join('\n'),
  };
}

// Emails EMAIL_REPLY_TO about a server error, only on Render, at most once an hour per error and route.
function createErrorAlert({ send = (...args) => emailService.sendAlertEmail(...args), now = Date.now, windowMs = WINDOW_MS } = {}) {
  const lastSent = new Map();

  return async function errorAlert(err, req, status) {
    const to = process.env.EMAIL_REPLY_TO;
    if (!process.env.RENDER || !to) return false;

    const time = now();
    const key = `${err?.name}|${err?.message}|${req.method} ${routeOf(req)}`;
    if (lastSent.size > MAX_TRACKED) {
      for (const [entry, sentAt] of lastSent) {
        if (time - sentAt >= windowMs) lastSent.delete(entry);
      }
    }
    const sentAt = lastSent.get(key);
    if (sentAt !== undefined && time - sentAt < windowMs) return false;
    lastSent.set(key, time);

    try {
      const { subject, text } = buildAlert(err, req, status, time);
      await send(to, subject, text);
      return true;
    } catch (sendError) {
      console.error('Could not send error alert:', sendError.message);
      return false;
    }
  };
}

const errorAlert = createErrorAlert();

module.exports = { createErrorAlert, errorAlert, buildAlert };
