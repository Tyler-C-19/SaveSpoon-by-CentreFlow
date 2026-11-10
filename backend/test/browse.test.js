// These tests replace database calls with mocks and never connect to the shared database.
process.env.JWT_SECRET = 'test-secret';

const { test, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');

const app = require('../src/app');
const User = require('../src/models/User');
const Listing = require('../src/models/Listing');
const { signToken } = require('../src/services/tokenService');

const makeUser = (role) => new User({ name: 'Test', email: `${role}@example.com`, role, emailVerified: true });

beforeEach(() => mock.restoreAll());

function signedInAs(user) {
  mock.method(User, 'findById', () => Promise.resolve(user));
  return signToken(user.id);
}

async function call(url, token) {
  const listener = app.listen(0);
  await new Promise((resolve) => listener.once('listening', resolve));
  try {
    const res = await globalThis.fetch(`http://127.0.0.1:${listener.address().port}${url}`, {
      headers: token ? { Authorization: `Bearer ${token}` } : {},
    });
    return { status: res.status, body: await res.json() };
  } finally {
    listener.closeAllConnections();
    await new Promise((resolve) => listener.close(resolve));
  }
}

function browse(found = []) {
  return mock.method(Listing, 'aggregate', async () => found);
}

const stage = (pipeline, name) => pipeline.find((item) => name in item)?.[name];

for (const url of ['/api/listings', '/api/listings/running-out']) {
  test(`GET ${url} returns 401 when not logged in`, async () => {
    assert.equal((await call(url)).status, 401);
  });

  test(`GET ${url} returns 403 for other roles`, async () => {
    for (const role of ['vendor', 'admin']) {
      const token = signedInAs(makeUser(role));
      assert.equal((await call(url, token)).status, 403, role);
      mock.restoreAll();
    }
  });

  test(`GET ${url} keeps only active, in-stock listings with an open pickup window`, async () => {
    const token = signedInAs(makeUser('customer'));
    const aggregate = browse();
    const before = Date.now();

    assert.equal((await call(url, token)).status, 200);

    const match = stage(aggregate.mock.calls[0].arguments[0], '$match');
    assert.equal(match.status, 'active');
    assert.equal(match.quantityAvailable.$gt, 0);
    assert.ok(match.pickupEnd.$gt.getTime() >= before);
  });

  test(`GET ${url} drops listings whose vendor no longer exists`, async () => {
    const token = signedInAs(makeUser('customer'));
    const aggregate = browse();

    await call(url, token);

    const pipeline = aggregate.mock.calls[0].arguments[0];
    assert.equal(stage(pipeline, '$lookup').from, 'vendors');
    assert.equal(stage(pipeline, '$unwind'), '$vendorProfile');
    const position = (name) => pipeline.findIndex((item) => name in item);
    assert.ok(position('$unwind') < position('$skip'));
    assert.ok(position('$unwind') < position('$limit'));
  });

  test(`GET ${url} returns the stall name but no private vendor details`, async () => {
    const token = signedInAs(makeUser('customer'));
    const aggregate = browse();

    await call(url, token);

    const fields = stage(aggregate.mock.calls[0].arguments[0], '$project');
    assert.equal(fields.stallName, '$vendorProfile.stallName');
    for (const hidden of ['vendor', 'vendorProfile', 'location', 'user', 'phone']) {
      assert.equal(fields[hidden], undefined, hidden);
    }
  });
}

test('browse sorts newest first and asks for one extra to detect more pages', async () => {
  const token = signedInAs(makeUser('customer'));
  const aggregate = browse();

  await call('/api/listings', token);

  const pipeline = aggregate.mock.calls[0].arguments[0];
  assert.deepEqual(stage(pipeline, '$sort'), { createdAt: -1, _id: -1 });
  assert.equal(stage(pipeline, '$skip'), 0);
  assert.equal(stage(pipeline, '$limit'), 21);
});

test('browse returns 20 listings and hasMore when another page exists', async () => {
  const token = signedInAs(makeUser('customer'));
  browse(Array.from({ length: 21 }, (_, index) => ({ _id: String(index) })));

  const res = await call('/api/listings', token);

  assert.equal(res.body.listings.length, 20);
  assert.equal(res.body.hasMore, true);
});

test('browse reports no more pages on the last page', async () => {
  const token = signedInAs(makeUser('customer'));
  browse([{ _id: '1' }]);

  const res = await call('/api/listings', token);

  assert.equal(res.body.listings.length, 1);
  assert.equal(res.body.hasMore, false);
});

test('browse skips earlier pages', async () => {
  const token = signedInAs(makeUser('customer'));
  const aggregate = browse();

  await call('/api/listings?page=3', token);

  assert.equal(stage(aggregate.mock.calls[0].arguments[0], '$skip'), 40);
});

test('browse rejects an invalid page without querying', async () => {
  const token = signedInAs(makeUser('customer'));
  const aggregate = browse();

  for (const page of ['0', '-1', '1.5', 'abc', '999999', '1&page=2']) {
    const res = await call(`/api/listings?page=${page}`, token);
    assert.equal(res.status, 400, page);
  }
  assert.equal(aggregate.mock.callCount(), 0);
});

test('running out keeps stock of 5 or fewer, lowest first, up to 6', async () => {
  const token = signedInAs(makeUser('customer'));
  const aggregate = browse();

  await call('/api/listings/running-out', token);

  const pipeline = aggregate.mock.calls[0].arguments[0];
  assert.deepEqual(stage(pipeline, '$match').quantityAvailable, { $gt: 0, $lte: 5 });
  assert.equal(stage(pipeline, '$sort').quantityAvailable, 1);
  assert.equal(stage(pipeline, '$limit'), 6);
});
