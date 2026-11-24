// These tests replace database calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Listing = require('../src/models/Listing');
const Favourite = require('../src/models/Favourite');
const { signToken } = require('../src/services/tokenService');
const { parseFilters } = require('../src/validators/searchFilters');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });
const stage = (pipeline, name) => pipeline.find((item) => name in item)?.[name];

let customer;
let token;
let calls;

beforeEach(() => {
  mock.restoreAll();
  customer = makeUser('customer');
  mock.method(User, 'findById', () => query(customer));
  token = signToken(customer.id);
  calls = [];
  mock.method(Listing, 'aggregate', async (pipeline) => {
    calls.push(pipeline);
    return [];
  });
});

const search = (params) => call(`/api/listings/search?${params}`, { token });

test('every filter and sort value is checked', () => {
  for (const bad of [
    { category: 'Pizza' }, { category: '' }, { category: ['Rice', 'Drinks'] }, { avoid: 'peanuts' },
    { halal: 'true' }, { favourites: '0' }, { openNow: 'yes' }, { maxPrice: '-1' }, { maxPrice: '1000' },
    { maxPrice: '3.555' }, { maxPrice: 'abc' }, { sort: 'distance' },
  ]) {
    assert.ok(parseFilters(bad).error, JSON.stringify(bad));
  }
  const good = parseFilters({ category: 'Rice,Noodles,Rice', avoid: 'egg,milk', halal: '1', maxPrice: '4.50', sort: 'price_asc' });
  assert.deepEqual(good.categories, ['Rice', 'Noodles']);
  assert.deepEqual(good.avoid, ['egg', 'milk']);
  assert.equal(good.maxPrice, 4.5);
  assert.equal(good.filtered, true);
  assert.equal(parseFilters({ sort: 'newest' }).filtered, false);
});

test('invalid filters are 400 without querying', async () => {
  for (const params of ['category=Pizza', 'q=nasi&maxPrice=abc', 'sort=distance', 'sort=best', 'halal=1&q=', 'q=nasi&page=0']) {
    const res = await search(params);
    assert.equal(res.status, 400, params);
  }
  assert.equal((await search('sort=best')).body.error, 'Best Match needs a keyword.');
  assert.equal(calls.length, 0);
});

test('without a keyword or filter the search is still refused', async () => {
  const res = await call('/api/listings/search', { token });
  assert.equal(res.status, 400);
  assert.equal(calls.length, 0);
});

test('filters alone list available listings, newest first, with no score', async () => {
  const before = Date.now();
  const res = await search('category=Rice,Noodles&halal=1&maxPrice=5&avoid=egg,milk&openNow=1');

  assert.equal(res.status, 200);
  const match = calls[0][0].$match;
  assert.equal(match.status, 'active');
  assert.equal(match.quantityAvailable.$gt, 0);
  assert.ok(new Date(match.pickupEnd.$gt).getTime() >= before);
  assert.deepEqual(match.category, { $in: ['Rice', 'Noodles'] });
  assert.equal(match.isHalal, true);
  assert.deepEqual(match.discountedPrice, { $lte: 5 });
  assert.deepEqual(match.allergens, { $nin: ['egg', 'milk'] });
  assert.ok(new Date(match.pickupStart.$lte).getTime() >= before);
  assert.deepEqual(stage(calls[0], '$sort'), { _listedAt: -1, _id: -1 });
  assert.equal(stage(calls[0], '$lookup').from, 'vendors');
  assert.equal(calls[0].some((item) => item.$addFields?._score), false);
  assert.deepEqual(res.body.otherStalls, []);
});

test('a keyword and filters combine, and other stalls are left out', async () => {
  const res = await search('q=nasi&halal=1');

  assert.equal(res.status, 200);
  const match = calls[0][0].$match;
  assert.equal(match.isHalal, true);
  assert.ok(calls[0].some((item) => item.$addFields?._score));
  assert.deepEqual(stage(calls[0], '$sort'), { _score: -1, _listedAt: -1, _id: -1 });
  assert.deepEqual(res.body.otherStalls, []);
  assert.equal(calls.length, 1);
});

test('each sort orders the results, ties newest first', async () => {
  const expected = {
    newest: { _listedAt: -1, _id: -1 },
    price_asc: { discountedPrice: 1, _listedAt: -1, _id: -1 },
    price_desc: { discountedPrice: -1, _listedAt: -1, _id: -1 },
    ending: { pickupEnd: 1, _listedAt: -1, _id: -1 },
    sold: { soldCount: -1, _listedAt: -1, _id: -1 },
    saving: { _saving: -1, _listedAt: -1, _id: -1 },
  };
  for (const [sort, order] of Object.entries(expected)) {
    calls = [];
    const res = await search(`sort=${sort}`);
    assert.equal(res.status, 200, sort);
    assert.deepEqual(stage(calls[0], '$sort'), order, sort);
  }
  calls = [];
  await search('q=nasi&sort=price_asc');
  assert.deepEqual(stage(calls[0], '$sort'), expected.price_asc);
});

test('Biggest Saving works out the share saved, and never divides by 0', async () => {
  await search('sort=saving');
  const saving = calls[0].find((item) => item.$addFields?._saving).$addFields._saving.$cond;
  assert.deepEqual(saving[0], { $gt: ['$originalPrice', 0] });
  assert.equal(saving[2], 0);
  assert.equal(stage(calls[0], '$project')._saving, undefined);
});

test("the Favourites filter keeps only this customer's favourites", async () => {
  const ids = [new mongoose.Types.ObjectId(), new mongoose.Types.ObjectId()];
  const distinct = mock.method(Favourite, 'distinct', async () => ids);

  await search('favourites=1');

  assert.deepEqual(distinct.mock.calls[0].arguments, ['listing', { customer: customer._id }]);
  assert.deepEqual(calls[0][0].$match._id, { $in: ids });
});

test('filtered results page 20 at a time', async () => {
  Listing.aggregate.mock.mockImplementation(async (pipeline) => {
    calls.push(pipeline);
    return Array.from({ length: 21 }, (_, index) => ({ _id: String(index) }));
  });

  const first = await search('category=Rice');
  const third = await search('category=Rice&page=3');

  assert.equal(first.body.listings.length, 20);
  assert.equal(first.body.hasMore, true);
  assert.equal(stage(calls[1], '$skip'), 40);
  assert.equal(third.body.otherStalls, undefined);
});

test('GET /api/listings/favourites needs a customer', async () => {
  assert.equal((await call('/api/listings/favourites')).status, 401);
  const vendor = makeUser('vendor');
  User.findById.mock.mockImplementation(() => query(vendor));
  assert.equal((await call('/api/listings/favourites', { token: signToken(vendor.id) })).status, 403);
});

test('the Favourites strip shows up to 6 available favourites, most recently added first', async () => {
  const ids = Array.from({ length: 8 }, () => new mongoose.Types.ObjectId());
  mock.method(Favourite, 'find', () => ({
    sort: () => ({ select: async () => ids.map((listing) => ({ listing })) }),
  }));
  // Returned in a different order; the query has already left out what isn't on sale.
  Listing.aggregate.mock.mockImplementation(async (pipeline) => {
    calls.push(pipeline);
    return [...ids].reverse().filter((id) => id !== ids[2]).map((id) => ({ _id: id }));
  });

  const res = await call('/api/listings/favourites', { token });

  assert.equal(res.status, 200);
  assert.deepEqual(res.body.listings.map((item) => item._id), [0, 1, 3, 4, 5, 6].map((index) => String(ids[index])));
  assert.equal(res.body.hasMore, true);
  const match = calls[0][0].$match;
  assert.equal(match.status, 'active');
  assert.deepEqual(match._id.$in.map(String), ids.map(String));
  assert.equal(stage(calls[0], '$project').stallName, '$vendorProfile.stallName');
});

test('no favourites means no listing query', async () => {
  mock.method(Favourite, 'find', () => ({ sort: () => ({ select: async () => [] }) }));

  const res = await call('/api/listings/favourites', { token });

  assert.deepEqual(res.body, { listings: [], hasMore: false });
  assert.equal(calls.length, 0);
});

test('hasMore is false when every available favourite fits in the strip', async () => {
  const ids = Array.from({ length: 6 }, () => new mongoose.Types.ObjectId());
  mock.method(Favourite, 'find', () => ({
    sort: () => ({ select: async () => ids.map((listing) => ({ listing })) }),
  }));
  Listing.aggregate.mock.mockImplementation(async () => ids.map((id) => ({ _id: id })));

  const res = await call('/api/listings/favourites', { token });

  assert.equal(res.body.listings.length, 6);
  assert.equal(res.body.hasMore, false);
});
