// These tests replace database calls with mocks and never connect to the shared database.
const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const { query, call } = require('./testServer');
const User = require('../src/models/User');
const Listing = require('../src/models/Listing');
const Favourite = require('../src/models/Favourite');
const { signToken } = require('../src/services/tokenService');
const { groupByStall } = require('../src/services/stallMapService');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });
const stage = (pipeline, name) => pipeline.find((item) => name in item)?.[name];

const pakDin = new mongoose.Types.ObjectId();
const cendana = new mongoose.Types.ObjectId();
const item = (stall, title, stallName, location = [103.6385, 1.559]) => ({
  _id: new mongoose.Types.ObjectId(),
  _stall: stall,
  title,
  stallName,
  pickupAddress: `${stallName} address`,
  location,
});

let calls;
let found;

function signIn(role) {
  const user = makeUser(role);
  mock.method(User, 'findById', () => query(user));
  return { user, token: signToken(user.id) };
}

beforeEach(() => {
  mock.restoreAll();
  calls = [];
  found = [];
  mock.method(Listing, 'aggregate', async (pipeline) => {
    calls.push(pipeline);
    return found;
  });
});

test('one marker per stall, counted, opened with its newest item, no vendor IDs', () => {
  const stalls = groupByStall([
    item(pakDin, 'Nasi Lemak', 'Warung Pak Din'),
    item(cendana, 'Mee Goreng', 'Kafe Cendana', [103.641, 1.5565]),
    item(pakDin, 'Teh Tarik', 'Warung Pak Din'),
  ]);

  assert.deepEqual(stalls.map((stall) => [stall.stallName, stall.count]), [['Kafe Cendana', 1], ['Warung Pak Din', 2]]);
  assert.equal(stalls[1].listing.title, 'Nasi Lemak');
  assert.deepEqual(stalls[0].location, [103.641, 1.5565]);
  assert.equal(stalls[0].address, 'Kafe Cendana address');
  assert.equal(JSON.stringify(stalls).includes(String(pakDin)), false);
  assert.equal(JSON.stringify(stalls).includes('_stall'), false);
});

test('each stall carries its first few matching items for the pane', () => {
  const titles = ['A', 'B', 'C', 'D', 'E'];
  const [stall] = groupByStall(titles.map((title) => item(pakDin, title, 'Warung Pak Din')));

  assert.equal(stall.count, 5);
  assert.deepEqual(stall.matches.map((match) => match.title), ['A', 'B', 'C', 'D']);
  assert.equal(JSON.stringify(stall.matches).includes('_stall'), false);
});

test('listings without a pin are left off the map', () => {
  assert.deepEqual(groupByStall([item(pakDin, 'Nasi Lemak', 'Warung Pak Din', null)]), []);
});

test('the map is for customers only', async () => {
  assert.equal((await call('/api/listings/map')).status, 401);
  const { token } = signIn('vendor');
  assert.equal((await call('/api/listings/map', { token })).status, 403);
  assert.equal(calls.length, 0);
});

test('without filters the map shows every stall with food on sale now', async () => {
  const { token } = signIn('customer');
  found = [item(pakDin, 'Nasi Lemak', 'Warung Pak Din')];
  const before = Date.now();

  const res = await call('/api/listings/map', { token });

  assert.equal(res.status, 200);
  assert.equal(res.body.stalls.length, 1);
  assert.equal(res.body.stalls[0].listing.title, 'Nasi Lemak');
  const match = calls[0][0].$match;
  assert.equal(match.status, 'active');
  assert.equal(match.quantityAvailable.$gt, 0);
  assert.ok(new Date(match.pickupEnd.$gt).getTime() >= before);
  assert.equal(stage(calls[0], '$project').location, '$location.coordinates');
  assert.equal(stage(calls[0], '$project')._stall, '$vendor');
  assert.equal(stage(calls[0], '$limit'), 500);
});

test("Search's keyword and filters apply to the map", async () => {
  const { user, token } = signIn('customer');
  const ids = [new mongoose.Types.ObjectId()];
  const distinct = mock.method(Favourite, 'distinct', async () => ids);

  const res = await call('/api/listings/map?q=nasi&halal=1&maxPrice=5&favourites=1', { token });

  assert.equal(res.status, 200);
  const match = calls[0][0].$match;
  assert.equal(match.isHalal, true);
  assert.deepEqual(match.discountedPrice, { $lte: 5 });
  assert.deepEqual(match._id, { $in: ids });
  assert.deepEqual(distinct.mock.calls[0].arguments, ['listing', { customer: user._id }]);
  assert.ok(calls[0].some((stageItem) => stageItem.$addFields?._score));
});

test('invalid map filters or keywords are 400 without querying', async () => {
  const { token } = signIn('customer');
  for (const params of ['category=Pizza', 'q=', `q=${'a'.repeat(51)}`, 'halal=yes', 'lat=99&lng=1']) {
    assert.equal((await call(`/api/listings/map?${params}`, { token })).status, 400, params);
  }
  assert.equal(calls.length, 0);
});
