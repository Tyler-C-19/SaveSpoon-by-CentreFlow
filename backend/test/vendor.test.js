// These tests replace database and Google calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');

const app = require('../src/app');
const User = require('../src/models/User');
const Vendor = require('../src/models/Vendor');
const Listing = require('../src/models/Listing');
const placesService = require('../src/services/placesService');
const { signToken } = require('../src/services/tokenService');
const { refreshVendorLocations } = require('../scripts/refreshVendorLocations');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });

const profile = {
  stallName: 'Warung Test',
  phone: '012-3456789',
  address: 'Cafeteria A, UTM Skudai',
  description: 'Rice and noodles',
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
};

beforeEach(() => mock.restoreAll());

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

async function call(url, { method = 'GET', body, token } = {}) {
  const listener = app.listen(0);
  await new Promise((resolve) => listener.once('listening', resolve));
  try {
    const res = await fetch(`http://127.0.0.1:${listener.address().port}${url}`, {
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

// AC4: access

for (const [method, url] of [
  ['GET', '/api/vendors/me'],
  ['POST', '/api/vendors/me'],
  ['PATCH', '/api/vendors/me'],
  ['GET', '/api/places/suggestions?q=skudai&sessionToken=abc'],
  ['GET', '/api/places/abc/location?sessionToken=abc'],
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

test('GET returns only the logged-in vendor profile', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  const findOne = mock.method(Vendor, 'findOne', async () => ({ stallName: 'Mine' }));

  const res = await call('/api/vendors/me', { token });

  assert.equal(res.status, 200);
  assert.deepEqual(findOne.mock.calls[0].arguments[0], { user: user._id });
});

test('GET returns 404 before setup', async () => {
  const token = signedInAs(makeUser('vendor'));
  mock.method(Vendor, 'findOne', async () => null);

  const res = await call('/api/vendors/me', { token });

  assert.equal(res.status, 404);
  assert.equal(res.body.code, 'NO_VENDOR_PROFILE');
});

// AC2 and AC4: creating a profile

test('POST stores the pin in [lng, lat] order', async () => {
  const token = signedInAs(makeUser('vendor'));
  const create = mock.method(Vendor, 'create', async (doc) => doc);

  const res = await call('/api/vendors/me', { method: 'POST', token, body: profile });

  assert.equal(res.status, 201);
  assert.deepEqual(create.mock.calls[0].arguments[0].location, {
    type: 'Point', coordinates: [103.6385, 1.559],
  });
});

test('POST ignores user and verified sent by the client', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  const create = mock.method(Vendor, 'create', async (doc) => doc);

  await call('/api/vendors/me', {
    method: 'POST', token, body: { ...profile, user: 'someone-else', verified: true },
  });

  const doc = create.mock.calls[0].arguments[0];
  assert.equal(doc.user, user._id);
  assert.equal('verified' in doc, false);
});

test('POST keeps the place ID when the pin came from a suggestion', async () => {
  const token = signedInAs(makeUser('vendor'));
  const create = mock.method(Vendor, 'create', async (doc) => doc);

  await call('/api/vendors/me', { method: 'POST', token, body: { ...profile, placeId: 'place-1' } });

  assert.equal(create.mock.calls[0].arguments[0].placeId, 'place-1');
});

test('POST leaves the place ID empty when the vendor placed the pin', async () => {
  const token = signedInAs(makeUser('vendor'));
  const create = mock.method(Vendor, 'create', async (doc) => doc);

  await call('/api/vendors/me', { method: 'POST', token, body: profile });

  assert.equal(create.mock.calls[0].arguments[0].placeId, undefined);
});

test('POST rejects a bad place ID', async () => {
  const token = signedInAs(makeUser('vendor'));
  const create = mock.method(Vendor, 'create', async (doc) => doc);

  const res = await call('/api/vendors/me', { method: 'POST', token, body: { ...profile, placeId: 'a/b' } });

  assert.equal(res.status, 400);
  assert.equal(create.mock.callCount(), 0);
});

test('a second POST returns 409', async () => {
  const token = signedInAs(makeUser('vendor'));
  mock.method(Vendor, 'create', async () => {
    throw Object.assign(new Error('duplicate'), { code: 11000 });
  });

  const res = await call('/api/vendors/me', { method: 'POST', token, body: profile });

  assert.equal(res.status, 409);
});

test('description is optional', async () => {
  const token = signedInAs(makeUser('vendor'));
  mock.method(Vendor, 'create', async (doc) => doc);
  const { description, ...required } = profile;

  const res = await call('/api/vendors/me', { method: 'POST', token, body: required });

  assert.equal(res.status, 201);
});

for (const [name, change] of [
  ['a short business name', { stallName: 'A' }],
  ['a long business name', { stallName: 'A'.repeat(81) }],
  ['a bad phone number', { phone: 'abc' }],
  ['a missing address', { address: ' ' }],
  ['a long address', { address: 'A'.repeat(201) }],
  ['a long description', { description: 'A'.repeat(501) }],
  ['a missing pin', { location: undefined }],
  ['one coordinate', { location: { type: 'Point', coordinates: [103.6] } }],
  ['coordinates as text', { location: { type: 'Point', coordinates: ['103.6', '1.5'] } }],
  ['longitude out of range', { location: { type: 'Point', coordinates: [181, 1.5] } }],
  ['latitude out of range', { location: { type: 'Point', coordinates: [103.6, 91] } }],
]) {
  test(`POST rejects ${name} and saves nothing`, async () => {
    const token = signedInAs(makeUser('vendor'));
    const create = mock.method(Vendor, 'create', async (doc) => doc);

    const res = await call('/api/vendors/me', { method: 'POST', token, body: { ...profile, ...change } });

    assert.equal(res.status, 400);
    assert.ok(res.body.error);
    assert.equal(create.mock.callCount(), 0);
  });
}

// AC5: description form

test('PATCH changes only the description', async () => {
  const user = makeUser('vendor');
  const token = signedInAs(user);
  const update = mock.method(Vendor, 'findOneAndUpdate', async () => ({ description: 'New' }));

  const res = await call('/api/vendors/me', {
    method: 'PATCH', token, body: { description: ' New ', stallName: 'Other', verified: true },
  });

  assert.equal(res.status, 200);
  const [filter, change] = update.mock.calls[0].arguments;
  assert.deepEqual(filter, { user: user._id });
  assert.deepEqual(change, { description: 'New' });
});

test('PATCH rejects a long description', async () => {
  const token = signedInAs(makeUser('vendor'));
  const update = mock.method(Vendor, 'findOneAndUpdate', async () => null);

  const res = await call('/api/vendors/me', { method: 'PATCH', token, body: { description: 'A'.repeat(501) } });

  assert.equal(res.status, 400);
  assert.equal(update.mock.callCount(), 0);
});

test('PATCH returns 404 before setup', async () => {
  const token = signedInAs(makeUser('vendor'));
  mock.method(Vendor, 'findOneAndUpdate', async () => null);

  const res = await call('/api/vendors/me', { method: 'PATCH', token, body: { description: 'New' } });

  assert.equal(res.status, 404);
});

// AC1: profile status in the session

test('/me says whether a vendor has a profile', async () => {
  const token = signedInAs(makeUser('vendor'));

  mock.method(Vendor, 'exists', async () => null);
  assert.equal((await call('/api/auth/me', { token })).body.user.hasVendorProfile, false);

  mock.restoreAll();
  const again = signedInAs(makeUser('vendor'));
  mock.method(Vendor, 'exists', async () => ({ _id: 'v1' }));
  assert.equal((await call('/api/auth/me', { token: again })).body.user.hasVendorProfile, true);
});

test('/me leaves the profile status off for customers', async () => {
  const token = signedInAs(makeUser('customer'));
  const exists = mock.method(Vendor, 'exists', async () => null);

  const res = await call('/api/auth/me', { token });

  assert.equal('hasVendorProfile' in res.body.user, false);
  assert.equal(exists.mock.callCount(), 0);
});

// AC3: address search

test('suggestions come from the search service', async () => {
  const token = signedInAs(makeUser('vendor'));
  const suggest = mock.method(placesService, 'suggest', async () => [{ placeId: 'p1', text: 'UTM Skudai' }]);

  const res = await call('/api/places/suggestions?q=%20skudai%20&sessionToken=abc', { token });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.suggestions, [{ placeId: 'p1', text: 'UTM Skudai' }]);
  assert.deepEqual(suggest.mock.calls[0].arguments, ['skudai', 'abc']);
});

test('short searches are rejected without calling the search service', async () => {
  const token = signedInAs(makeUser('vendor'));
  const suggest = mock.method(placesService, 'suggest', async () => []);

  const res = await call('/api/places/suggestions?q=ab&sessionToken=abc', { token });

  assert.equal(res.status, 400);
  assert.equal(suggest.mock.callCount(), 0);
});

test('a place id with a path in it is rejected', async () => {
  const token = signedInAs(makeUser('vendor'));
  const locate = mock.method(placesService, 'locate', async () => ({ lat: 1, lng: 2 }));

  const res = await call('/api/places/a.b/location?sessionToken=abc', { token });

  assert.equal(res.status, 400);
  assert.equal(locate.mock.callCount(), 0);
});

test('a failed search returns 503 so the vendor can place the pin by hand', async () => {
  const token = signedInAs(makeUser('vendor'));
  const error = mock.method(console, 'error', () => {});
  mock.method(placesService, 'suggest', async () => {
    throw new placesService.PlacesError('down');
  });

  const res = await call('/api/places/suggestions?q=skudai&sessionToken=abc', { token });

  assert.equal(res.status, 503);
  assert.match(res.body.error, /pin/);
  assert.equal(error.mock.callCount(), 1);
});

// Coordinate refresh script

test('refresh updates only vendors with a place ID, and their listings, in [lng, lat] order', async () => {
  const find = mock.method(Vendor, 'find', async () => [{ _id: 'v1', placeId: 'place-1', stallName: 'One' }]);
  const locate = mock.method(placesService, 'locate', async () => ({ lat: 1.5, lng: 103.6 }));
  const vendorUpdate = mock.method(Vendor, 'updateOne', async () => ({}));
  const listingUpdate = mock.method(Listing, 'updateMany', async () => ({}));

  const result = await refreshVendorLocations();

  const location = { type: 'Point', coordinates: [103.6, 1.5] };
  assert.deepEqual(find.mock.calls[0].arguments[0], { placeId: { $exists: true, $ne: null } });
  assert.deepEqual(locate.mock.calls[0].arguments, ['place-1']);
  assert.deepEqual(vendorUpdate.mock.calls[0].arguments, [{ _id: 'v1' }, { location }]);
  assert.deepEqual(listingUpdate.mock.calls[0].arguments, [{ vendor: 'v1' }, { location }]);
  assert.deepEqual(result, { refreshed: 1, failed: [] });
});

test('refresh reports a failed vendor, changes it nowhere and carries on', async () => {
  mock.method(Vendor, 'find', async () => [
    { _id: 'v1', placeId: 'gone', stallName: 'One' },
    { _id: 'v2', placeId: 'place-2', stallName: 'Two' },
  ]);
  mock.method(placesService, 'locate', async (placeId) => {
    if (placeId === 'gone') throw new placesService.PlacesError('Places API returned 404');
    return { lat: 1.5, lng: 103.6 };
  });
  const vendorUpdate = mock.method(Vendor, 'updateOne', async () => ({}));
  mock.method(Listing, 'updateMany', async () => ({}));

  const result = await refreshVendorLocations();

  assert.equal(vendorUpdate.mock.callCount(), 1);
  assert.deepEqual(vendorUpdate.mock.calls[0].arguments[0], { _id: 'v2' });
  assert.deepEqual(result, {
    refreshed: 1,
    failed: [{ stallName: 'One', reason: 'Places API returned 404' }],
  });
});

test('the search service reports a missing API key as a search failure', async () => {
  const key = process.env.GOOGLE_PLACES_API_KEY;
  delete process.env.GOOGLE_PLACES_API_KEY;
  const request = mock.method(globalThis, 'fetch', async () => {
    throw new Error('should not be called');
  });

  await assert.rejects(placesService.suggest('skudai', 'abc'), placesService.PlacesError);
  assert.equal(request.mock.callCount(), 0);
  if (key) process.env.GOOGLE_PLACES_API_KEY = key;
});
