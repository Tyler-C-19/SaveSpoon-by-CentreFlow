// These tests replace database calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Listing = require('../src/models/Listing');
const Favourite = require('../src/models/Favourite');
const { signToken } = require('../src/services/tokenService');

const LISTING_ID = String(new mongoose.Types.ObjectId());
const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });

let saved;

function signedInAs(user) {
  mock.method(User, 'findById', () => query(user));
  return signToken(user.id);
}

beforeEach(() => {
  mock.restoreAll();
  saved = [];
  mock.method(Listing, 'exists', async () => ({ _id: LISTING_ID }));
  mock.method(Favourite, 'exists', async () => null);
  mock.method(Favourite, 'countDocuments', async () => 0);
  mock.method(Favourite, 'create', async (doc) => saved.push(doc));
  mock.method(Favourite, 'deleteOne', async () => ({ deletedCount: 1 }));
});

for (const [method, url] of [['GET', '/api/favourites/ids'], ['PUT', `/api/favourites/${LISTING_ID}`], ['DELETE', `/api/favourites/${LISTING_ID}`]]) {
  test(`${method} ${url} needs a customer`, async () => {
    assert.equal((await call(url, { method })).status, 401);
    const token = signedInAs(makeUser('vendor'));
    assert.equal((await call(url, { method, token })).status, 403);
  });
}

test('the IDs come back newest first', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  let sortedBy;
  mock.method(Favourite, 'find', (filter) => {
    assert.deepEqual(filter, { customer: user._id });
    return {
      sort(order) {
        sortedBy = order;
        return { select: async () => [{ listing: 'b' }, { listing: 'a' }] };
      },
    };
  });

  const res = await call('/api/favourites/ids', { token });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { listingIds: ['b', 'a'] });
  assert.deepEqual(sortedBy, { createdAt: -1, _id: -1 });
});

test('adding saves the customer and listing', async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);

  const res = await call(`/api/favourites/${LISTING_ID}`, { method: 'PUT', token });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { listingId: LISTING_ID, favourite: true });
  assert.equal(saved.length, 1);
  assert.equal(String(saved[0].customer), String(user._id));
  assert.equal(saved[0].listing, LISTING_ID);
});

test('adding one already saved changes nothing', async () => {
  const token = signedInAs(makeUser('customer'));
  Favourite.exists.mock.mockImplementation(async () => ({ _id: 'f1' }));

  const res = await call(`/api/favourites/${LISTING_ID}`, { method: 'PUT', token });

  assert.equal(res.status, 200);
  assert.equal(saved.length, 0);
});

test('adding at the same moment twice still succeeds', async () => {
  const token = signedInAs(makeUser('customer'));
  Favourite.create.mock.mockImplementation(async () => {
    throw Object.assign(new Error('duplicate'), { code: 11000 });
  });

  const res = await call(`/api/favourites/${LISTING_ID}`, { method: 'PUT', token });

  assert.equal(res.status, 200);
  assert.equal(res.body.favourite, true);
});

test('a missing or invalid listing is 404', async () => {
  const token = signedInAs(makeUser('customer'));
  Listing.exists.mock.mockImplementation(async () => null);

  const gone = await call(`/api/favourites/${LISTING_ID}`, { method: 'PUT', token });
  const invalid = await call('/api/favourites/not-an-id', { method: 'PUT', token });

  for (const res of [gone, invalid]) {
    assert.equal(res.status, 404);
    assert.equal(res.body.error, 'This item is no longer available.');
  }
  assert.equal(saved.length, 0);
});

test('the 201st favourite is refused', async () => {
  const token = signedInAs(makeUser('customer'));
  Favourite.countDocuments.mock.mockImplementation(async () => 200);

  const res = await call(`/api/favourites/${LISTING_ID}`, { method: 'PUT', token });

  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'FAVOURITES_FULL');
  assert.equal(res.body.error, 'You can save up to 200 Favourites.');
  assert.equal(saved.length, 0);
});

test("removing deletes only this customer's favourite, even if the listing is gone", async () => {
  const user = makeUser('customer');
  const token = signedInAs(user);
  Listing.exists.mock.mockImplementation(async () => null);

  const res = await call(`/api/favourites/${LISTING_ID}`, { method: 'DELETE', token });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { listingId: LISTING_ID, favourite: false });
  const [filter] = Favourite.deleteOne.mock.calls[0].arguments;
  assert.deepEqual(filter, { customer: user._id, listing: LISTING_ID });
});

test('removing with an invalid ID touches nothing', async () => {
  const token = signedInAs(makeUser('customer'));

  const res = await call('/api/favourites/not-an-id', { method: 'DELETE', token });

  assert.equal(res.status, 200);
  assert.equal(Favourite.deleteOne.mock.callCount(), 0);
});

test('sample Favourites match seeded titles, newest last, and the reset clears them', () => {
  const { sampleFavourites } = require('../seed/sampleFavourites');
  const fs = require('fs');
  const path = require('path');
  const customers = [{ _id: 'c1' }, { _id: 'c2' }];
  const titles = ['Nasi Campur Set', 'Mee Goreng Mamak', 'Assorted Kuih Box', 'Chicken Sandwich'];
  const listings = titles.map((title, index) => ({ _id: `l${index}`, title }));

  const docs = sampleFavourites(customers, listings, 1_000_000);

  assert.deepEqual(docs.map((doc) => [doc.customer, doc.listing]), [['c1', 'l2'], ['c1', 'l1'], ['c1', 'l0'], ['c2', 'l3']]);
  assert.ok(docs[2].createdAt > docs[0].createdAt);
  assert.deepEqual(sampleFavourites(customers, []), []);
  const seed = fs.readFileSync(path.join(__dirname, '..', 'seed', 'seed.js'), 'utf8');
  assert.match(seed, /Favourite\.deleteMany\(\{\}\)/);
});

test('sample listings only use statuses the app writes, so vendors can still edit them', () => {
  const { sampleListings } = require('../seed/sampleListings');
  const stall = () => ({ _id: new mongoose.Types.ObjectId() });
  for (const fields of sampleListings([stall(), stall(), stall()])) {
    assert.ok([undefined, 'active', 'paused'].includes(fields.status), fields.title);
  }
});
