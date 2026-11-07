const placesService = require('../services/placesService');
const { isText } = require('../validators/authValidators');

const UNAVAILABLE = { error: 'Address search is unavailable. Place the pin on the map instead.' };
const TOKEN_PATTERN = /^[\w-]{1,36}$/;
const PLACE_ID_PATTERN = /^[\w-]{1,512}$/;

async function respond(res, work) {
  try {
    return res.json(await work());
  } catch (err) {
    console.error('Address search failed:', err.message);
    return res.status(503).json(UNAVAILABLE);
  }
}

async function suggestions(req, res) {
  const { q, sessionToken } = req.query;
  if (!isText(q) || q.trim().length < 3 || q.trim().length > 200 || !TOKEN_PATTERN.test(sessionToken)) {
    return res.status(400).json({ error: 'Enter at least 3 characters to search.' });
  }
  return respond(res, async () => ({
    suggestions: await placesService.suggest(q.trim(), sessionToken),
  }));
}

async function location(req, res) {
  const { sessionToken } = req.query;
  if (!PLACE_ID_PATTERN.test(req.params.placeId) || !TOKEN_PATTERN.test(sessionToken)) {
    return res.status(400).json({ error: 'That place could not be found.' });
  }
  return respond(res, async () => ({
    location: await placesService.locate(req.params.placeId, sessionToken),
  }));
}

module.exports = { suggestions, location };
