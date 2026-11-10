// These tests replace database and Gemini calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const app = require('../src/app');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const geminiService = require('../src/services/geminiService');
const { signToken } = require('../src/services/tokenService');
const { listingError } = require('../src/validators/listingValidators');
const { sampleListings } = require('../seed/sampleListings');
const { createUsageLimiter } = require('../src/services/usageLimiter');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });
const inHours = (hours) => new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();

const validListing = () => ({
  title: 'Nasi Lemak',
  description: 'With sambal',
  category: 'Rice',
  isHalal: true,
  originalPrice: 8,
  discountedPrice: 4.5,
  quantityAvailable: 6,
  pickupStart: inHours(1),
  pickupEnd: inHours(3),
  allergens: ['egg'],
});

const makeVendor = (user) => ({
  _id: new mongoose.Types.ObjectId(),
  user: user._id,
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
});

beforeEach(() => {
  mock.restoreAll();
  delete process.env.GEMINI_API_KEY;
  delete process.env.GEMINI_MODEL;
});

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

async function call(url, { method = 'GET', body, token } = {}) {
  const listener = app.listen(0);
  await new Promise((resolve) => listener.once('listening', resolve));
  try {
    const res = await globalThis.fetch(`http://127.0.0.1:${listener.address().port}${url}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: res.status, body: await res.json() };
  } finally {
    listener.closeAllConnections();
    await new Promise((resolve) => listener.close(resolve));
  }
}

for (const [method, url] of [
  ['POST', '/api/listings'],
  ['GET', '/api/listings/mine'],
  ['POST', '/api/listings/allergen-suggestions'],
]) {
  test(`${method} ${url} returns 401 when not logged in`, async () => {
    assert.equal((await call(url, { method })).status, 401);
  });

  test(`${method} ${url} returns 403 for other roles`, async () => {
    for (const role of ['customer', 'admin']) {
      const token = signedInAs(makeUser(role));
      assert.equal((await call(url, { method, token })).status, 403, role);
      mock.restoreAll();
    }
  });
}

test('create returns NO_VENDOR_PROFILE and saves nothing without a profile', async () => {
  const token = signedInAs(makeUser('vendor'));
  mock.method(Vendor, 'findOne', async () => null);
  const create = mock.method(Listing, 'create', async () => ({}));

  const res = await call('/api/listings', { method: 'POST', token, body: validListing() });

  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'NO_VENDOR_PROFILE');
  assert.equal(create.mock.callCount(), 0);
});

test('create saves an active listing using the vendor and location from the server', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  const vendor = makeVendor(user);
  mock.method(Vendor, 'findOne', async () => vendor);
  const create = mock.method(Listing, 'create', async (fields) => new Listing(fields));

  const res = await call('/api/listings', {
    method: 'POST',
    token,
    body: {
      ...validListing(),
      vendor: new mongoose.Types.ObjectId().toString(),
      location: { type: 'Point', coordinates: [1, 2] },
      status: 'sold_out',
      imageUrl: 'https://example.com/fake.png',
    },
  });

  assert.equal(res.status, 201);
  const saved = create.mock.calls[0].arguments[0];
  assert.equal(saved.vendor, vendor._id);
  assert.deepEqual(saved.location.coordinates, [103.6385, 1.559]);
  assert.equal('status' in saved, false);
  assert.equal('imageUrl' in saved, false);
  assert.equal(res.body.listing.status, 'active');
  assert.equal(res.body.listing.imageUrl, null);
});

test('create removes repeated allergens and defaults to none', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  mock.method(Vendor, 'findOne', async () => makeVendor(user));
  const create = mock.method(Listing, 'create', async (fields) => new Listing(fields));

  await call('/api/listings', { method: 'POST', token, body: { ...validListing(), allergens: ['egg', 'egg'] } });
  const { allergens, ...withoutAllergens } = validListing();
  assert.deepEqual(allergens, ['egg']);
  await call('/api/listings', { method: 'POST', token, body: withoutAllergens });

  assert.deepEqual(create.mock.calls[0].arguments[0].allergens, ['egg']);
  assert.deepEqual(create.mock.calls[1].arguments[0].allergens, []);
});

test('create rejects invalid input and saves nothing', async () => {
  const token = signedInAs(makeUser('vendor'));
  const create = mock.method(Listing, 'create', async () => ({}));

  const res = await call('/api/listings', {
    method: 'POST',
    token,
    body: { ...validListing(), discountedPrice: 9 },
  });

  assert.equal(res.status, 400);
  assert.match(res.body.error, /less than the original/);
  assert.equal(create.mock.callCount(), 0);
});

const rejected = [
  ['short title', { title: 'A' }],
  ['long title', { title: 'A'.repeat(81) }],
  ['long description', { description: 'A'.repeat(501) }],
  ['unknown category', { category: 'Soup' }],
  ['missing halal answer', { isHalal: undefined }],
  ['halal given as text', { isHalal: 'yes' }],
  ['zero original price', { originalPrice: 0 }],
  ['three decimal original price', { originalPrice: 8.123 }],
  ['zero discounted price', { discountedPrice: 0 }],
  ['discounted price equal to original', { discountedPrice: 8 }],
  ['price given as text', { originalPrice: '8' }],
  ['zero stock', { quantityAvailable: 0 }],
  ['stock above 999', { quantityAvailable: 1000 }],
  ['fractional stock', { quantityAvailable: 1.5 }],
  ['invalid pickup date', { pickupStart: 'soon' }],
  ['pickup ending before it starts', { pickupStart: inHours(3), pickupEnd: inHours(2) }],
  ['pickup ending in the past', { pickupStart: inHours(-3), pickupEnd: inHours(-1) }],
  ['pickup ending after 24 hours', { pickupEnd: inHours(25) }],
  ['unknown allergen', { allergens: ['dust'] }],
  ['allergens not given as a list', { allergens: 'egg' }],
  ['other allergens not given as a list', { otherAllergens: 'mango' }],
  ['too many other allergens', { otherAllergens: ['aa', 'bb', 'cc', 'dd', 'ee', 'ff'] }],
  ['one letter other allergen', { otherAllergens: ['a'] }],
  ['other allergen with symbols', { otherAllergens: ['<script>'] }],
];

for (const [name, change] of rejected) {
  test(`validator rejects ${name}`, () => {
    assert.notEqual(listingError({ ...validListing(), ...change }), null);
  });
}

test('validator accepts a valid listing, two decimal prices and a pickup that already started', () => {
  assert.equal(listingError(validListing()), null);
  assert.equal(listingError({ ...validListing(), originalPrice: 8.1, discountedPrice: 4.55 }), null);
  assert.equal(listingError({ ...validListing(), pickupStart: inHours(-1) }), null);
});

test('mine returns only the vendor listings, newest first', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  const vendor = makeVendor(user);
  mock.method(Vendor, 'findOne', async () => vendor);
  const sort = mock.fn(async () => [{ title: 'Mine' }]);
  const find = mock.method(Listing, 'find', () => ({ sort }));

  const res = await call('/api/listings/mine', { token });

  assert.equal(res.status, 200);
  assert.deepEqual(find.mock.calls[0].arguments[0], { vendor: vendor._id });
  assert.deepEqual(sort.mock.calls[0].arguments[0], { createdAt: -1 });
  assert.deepEqual(res.body.listings, [{ title: 'Mine' }]);
});

test('mine returns NO_VENDOR_PROFILE without a profile', async () => {
  const token = signedInAs(makeUser('vendor'));
  mock.method(Vendor, 'findOne', async () => null);

  const res = await call('/api/listings/mine', { token });

  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'NO_VENDOR_PROFILE');
});

test('suggestion returns allergens using only the item name and description', async () => {
  const token = signedInAs(makeUser('vendor'));
  const answer = { allergens: ['egg', 'gluten'], otherAllergens: ['mango'] };
  const suggest = mock.method(geminiService, 'suggestAllergens', async () => answer);

  const res = await call('/api/listings/allergen-suggestions', {
    method: 'POST',
    token,
    body: { title: ' Egg Sandwich ', description: ' Toasted ', phone: '012-3456789' },
  });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body, answer);
  assert.deepEqual(suggest.mock.calls[0].arguments, ['Egg Sandwich', 'Toasted']);
});

test('suggestion needs an item name', async () => {
  const token = signedInAs(makeUser('vendor'));
  const suggest = mock.method(geminiService, 'suggestAllergens', async () => ({}));

  const res = await call('/api/listings/allergen-suggestions', { method: 'POST', token, body: {} });

  assert.equal(res.status, 400);
  assert.equal(suggest.mock.callCount(), 0);
});

test('suggestion failure returns 503 without showing the cause', async () => {
  const token = signedInAs(makeUser('vendor'));
  mock.method(console, 'error', () => {});
  mock.method(geminiService, 'suggestAllergens', async () => {
    throw new geminiService.GeminiError('secret detail');
  });

  const res = await call('/api/listings/allergen-suggestions', {
    method: 'POST',
    token,
    body: { title: 'Egg Sandwich' },
  });

  assert.equal(res.status, 503);
  assert.doesNotMatch(res.body.error, /secret/);
  assert.match(res.body.error, /temporarily unavailable.*Try again later.*manually/);
});

function geminiReturns(text, { ok = true, status = 200 } = {}) {
  process.env.GEMINI_API_KEY = 'test-key';
  return mock.method(globalThis, 'fetch', async () => ({
    ok,
    status,
    json: async () => ({ candidates: [{ content: { parts: [{ text }] } }] }),
  }));
}

test('Gemini service sends the key in a header and limits answers to the allergen list', async () => {
  const request = geminiReturns(JSON.stringify({
    allergens: ['egg', 'egg', 'dust', 'gluten'],
    otherAllergens: ['Mango', 'mango', 'Milk', '<b>bad</b>', 5, 'kiwi', 'lime', 'plum', 'pear', 'fig'],
  }));

  const allergens = await geminiService.suggestAllergens('Egg Sandwich', 'Toasted');

  assert.deepEqual(allergens, {
    allergens: ['egg', 'gluten', 'milk'],
    otherAllergens: ['Mango', 'Kiwi', 'Lime'],
  });
  const [url, options] = request.mock.calls[0].arguments;
  assert.equal(url.includes('test-key'), false);
  assert.equal(options.headers['x-goog-api-key'], 'test-key');
  assert.match(options.body, /Egg Sandwich/);
  assert.match(options.body, /Description: Toasted/);
  assert.ok(
    JSON.parse(options.body).generationConfig.responseSchema.properties.allergens.items.enum.includes('coconut'),
  );
});

test('Gemini service puts other allergens in title case', async () => {
  geminiReturns(JSON.stringify({
    allergens: [],
    otherAllergens: [' cashew ', 'BUAH KERAS', 'Cili Padi', 'cashew'],
  }));

  const allergens = await geminiService.suggestAllergens('Nasi Lemak', '');

  assert.deepEqual(allergens.otherAllergens, ['Cashew', 'Buah Keras', 'Cili Padi']);
});

test('Gemini service uses the model setting', async () => {
  const request = geminiReturns('{"allergens":[],"otherAllergens":[]}');
  process.env.GEMINI_MODEL = 'test-model';

  await geminiService.suggestAllergens('Rice');

  assert.match(request.mock.calls[0].arguments[0], /test-model:generateContent/);
});

test('Gemini service fails without a key, on an error status and on invalid answers', async () => {
  await assert.rejects(geminiService.suggestAllergens('Rice'), geminiService.GeminiError);

  geminiReturns('[]', { ok: false, status: 429 });
  await assert.rejects(geminiService.suggestAllergens('Rice'), /429/);
  mock.restoreAll();

  geminiReturns('not json');
  await assert.rejects(geminiService.suggestAllergens('Rice'), geminiService.GeminiError);
  mock.restoreAll();

  geminiReturns('["egg"]');
  await assert.rejects(geminiService.suggestAllergens('Rice'), geminiService.GeminiError);
});

test('create stores other allergens and moves listed names into allergens', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  mock.method(Vendor, 'findOne', async () => makeVendor(user));
  const create = mock.method(Listing, 'create', async (fields) => new Listing(fields));

  await call('/api/listings', {
    method: 'POST',
    token,
    body: { ...validListing(), otherAllergens: [' Mango ', 'mango', 'Milk'] },
  });

  const saved = create.mock.calls[0].arguments[0];
  assert.deepEqual(saved.allergens, ['egg', 'milk']);
  assert.deepEqual(saved.otherAllergens, ['Mango']);
});

test('create puts typed other allergens in title case', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  mock.method(Vendor, 'findOne', async () => makeVendor(user));
  const create = mock.method(Listing, 'create', async (fields) => new Listing(fields));

  await call('/api/listings', {
    method: 'POST',
    token,
    body: {
      ...validListing(),
      otherAllergens: ['cashew', 'bUAH  kERAS', "bird's eye chilli", 'kuih-muih', 'BELACAN'],
    },
  });

  const saved = create.mock.calls[0].arguments[0];
  assert.deepEqual(saved.otherAllergens, ['Cashew', 'Buah Keras', "Bird's Eye Chilli", 'Kuih-Muih']);
  assert.ok(saved.allergens.includes('belacan'));
});

test('a vendor reaching the suggestion limit gets a clear message and no Gemini call', async () => {
  const token = signedInAs(makeUser('vendor'));
  const answer = { allergens: [], otherAllergens: [] };
  const suggest = mock.method(geminiService, 'suggestAllergens', async () => answer);
  const send = () => call('/api/listings/allergen-suggestions', {
    method: 'POST',
    token,
    body: { title: 'Egg Sandwich' },
  });

  for (let i = 0; i < 10; i += 1) assert.equal((await send()).status, 200);
  const res = await send();

  assert.equal(res.status, 429);
  assert.match(res.body.error, /reached the AI suggestion limit/);
  assert.equal(suggest.mock.callCount(), 10);
});

test('the suggestion limit is per vendor and ignores invalid requests', async () => {
  const first = signedInAs(makeUser('vendor'));
  mock.method(geminiService, 'suggestAllergens', async () => ({ allergens: [], otherAllergens: [] }));
  for (let i = 0; i < 11; i += 1) {
    await call('/api/listings/allergen-suggestions', { method: 'POST', token: first, body: {} });
  }
  const valid = await call('/api/listings/allergen-suggestions', {
    method: 'POST',
    token: first,
    body: { title: 'Egg Sandwich' },
  });
  assert.equal(valid.status, 200);

  mock.restoreAll();
  const second = signedInAs(makeUser('vendor'));
  mock.method(geminiService, 'suggestAllergens', async () => ({ allergens: [], otherAllergens: [] }));
  const other = await call('/api/listings/allergen-suggestions', {
    method: 'POST',
    token: second,
    body: { title: 'Egg Sandwich' },
  });
  assert.equal(other.status, 200);
});

test('the limiter allows use again after the window ends', () => {
  let time = 0;
  const limiter = createUsageLimiter({ limit: 1, windowMs: 1000, now: () => time });

  assert.equal(limiter.take('a').allowed, true);
  assert.deepEqual(limiter.take('a'), { allowed: false, retryAfterMs: 1000 });
  time = 1000;
  assert.equal(limiter.take('a').allowed, true);
});

test('sample listings meet the listing rules', () => {
  const stall = () => ({
    _id: new mongoose.Types.ObjectId(),
    location: { type: 'Point', coordinates: [103.6385, 1.559] },
  });

  const listings = sampleListings([stall(), stall(), stall()]);

  assert.equal(listings.length, 6);
  for (const fields of listings) {
    assert.equal(new Listing(fields).validateSync(), undefined, fields.title);
  }
});
