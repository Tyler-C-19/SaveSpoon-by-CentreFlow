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

// Evaluates the small set of expressions the search pipeline uses.
function evaluate(expr, doc) {
  if (typeof expr === 'string' && expr.startsWith('$')) {
    return expr.slice(1).split('.').reduce((value, key) => value?.[key], doc);
  }
  if (expr === null || typeof expr !== 'object' || Array.isArray(expr)) return expr;
  const [op, args] = Object.entries(expr)[0];
  switch (op) {
    case '$add':
      return args.reduce((sum, item) => sum + evaluate(item, doc), 0);
    case '$cond':
      return evaluate(args[0], doc) ? evaluate(args[1], doc) : evaluate(args[2], doc);
    case '$ifNull':
      return evaluate(args[0], doc) ?? evaluate(args[1], doc);
    case '$gt':
      return evaluate(args[0], doc) > evaluate(args[1], doc);
    case '$and':
      return args.every((item) => evaluate(item, doc));
    case '$regexMatch':
      return new RegExp(args.regex, args.options).test(evaluate(args.input, doc));
    default:
      throw new Error(`Unsupported ${op}`);
  }
}

function runSearchStages(pipeline, docs) {
  let rows = docs;
  for (const stage of pipeline) {
    if (stage.$addFields) {
      rows = rows.map((row) => ({
        ...row,
        ...Object.fromEntries(Object.entries(stage.$addFields).map(([key, expr]) => [key, evaluate(expr, row)])),
      }));
    } else if (stage.$match?.$expr) {
      rows = rows.filter((row) => evaluate(stage.$match.$expr, row));
    }
  }
  return rows.sort((a, b) => b._score - a._score || b.createdAt - a.createdAt);
}

const doc = (title, fields = {}) => ({
  title,
  category: 'Rice',
  description: '',
  createdAt: 1,
  vendorProfile: { stallName: 'Warung Pak Din' },
  ...fields,
});

const SAMPLES = [
  doc('Ayam Goreng Rice', { description: 'Fried chicken with rice and sambal' }),
  doc('Nasi Lemak Ayam', { description: 'Coconut rice with fried chicken and sambal' }),
  doc('Mee Goreng Mamak', { category: 'Noodles', description: 'Spicy fried noodles with egg', vendorProfile: { stallName: 'Kafe Cendana' } }),
  doc('Kuey Teow Goreng', { category: 'Noodles', description: 'Fried flat noodles', vendorProfile: { stallName: 'Kafe Cendana' } }),
  doc('Nasigoreng Special', { createdAt: 2 }),
  doc('Teh Tarik', { category: 'Drinks', description: 'Pulled milk tea', vendorProfile: { stallName: 'Kafe Cendana' } }),
  doc('Bubur Cha Cha', { category: 'Desserts', description: 'Sweet potato in coconut milk' }),
  doc('Ayam Penyet', { description: 'Smashed fried chicken with rice, tofu, tempeh and sambal', vendorProfile: { stallName: 'Roti Bakar Kak Ina' } }),
];

async function searchFor(query, docs = SAMPLES) {
  const token = signedInAs(makeUser('customer'));
  const calls = [];
  mock.method(Listing, 'aggregate', async (pipeline) => {
    calls.push(pipeline);
    return [];
  });
  const res = await call(`/api/listings/search?q=${encodeURIComponent(query)}`, token);
  assert.equal(res.status, 200, query);
  return { titles: runSearchStages(calls[0], docs).map((row) => row.title), pipeline: calls[0], calls };
}

const stage = (pipeline, name) => pipeline.find((item) => name in item)?.[name];

test('GET /api/listings/search returns 401 when not logged in', async () => {
  assert.equal((await call('/api/listings/search?q=nasi')).status, 401);
});

test('GET /api/listings/search returns 403 for other roles', async () => {
  for (const role of ['vendor', 'admin']) {
    const token = signedInAs(makeUser(role));
    assert.equal((await call('/api/listings/search?q=nasi', token)).status, 403, role);
    mock.restoreAll();
  }
});

test('search rejects a missing, blank or over-long keyword without querying', async () => {
  const token = signedInAs(makeUser('customer'));
  const aggregate = mock.method(Listing, 'aggregate', async () => []);

  for (const query of ['', '?q=', '?q=%20%20%20', `?q=${'a'.repeat(51)}`, '?q=a&q=b', '?q=nasi&page=0']) {
    const res = await call(`/api/listings/search${query}`, token);
    assert.equal(res.status, 400, query);
  }
  assert.equal(aggregate.mock.callCount(), 0);
});

test('search allows 1 character and 50 after trimming spaces', async () => {
  const token = signedInAs(makeUser('customer'));
  mock.method(Listing, 'aggregate', async () => []);

  for (const query of ['a', `  ${'a'.repeat(50)}  `, 'nasi    lemak']) {
    const res = await call(`/api/listings/search?q=${encodeURIComponent(query)}`, token);
    assert.equal(res.status, 200, query);
  }
});

test('search keeps only available listings whose vendor still exists', async () => {
  const before = Date.now();
  const { pipeline } = await searchFor('nasi');

  const match = pipeline[0].$match;
  assert.equal(match.status, 'active');
  assert.equal(match.quantityAvailable.$gt, 0);
  assert.ok(match.pickupEnd.$gt.getTime() >= before);
  assert.equal(stage(pipeline, '$lookup').from, 'vendors');
  assert.equal(stage(pipeline, '$unwind'), '$vendorProfile');
});

test('search returns the stall name but no private vendor details', async () => {
  const { pipeline } = await searchFor('nasi');

  const fields = stage(pipeline, '$project');
  assert.equal(fields.stallName, '$vendorProfile.stallName');
  assert.equal(fields.pickupAddress, '$vendorProfile.address');
  for (const hidden of ['vendor', 'vendorProfile', 'location', 'user', 'phone', '_score']) {
    assert.equal(fields[hidden], undefined, hidden);
  }
});

test('search ignores case and matches part of a word', async () => {
  assert.deepEqual((await searchFor('NAS')).titles, ['Nasigoreng Special', 'Nasi Lemak Ayam']);
  assert.ok((await searchFor('lemak')).titles.includes('Nasi Lemak Ayam'));
});

test('every word must match, in any of the searched fields', async () => {
  const { titles } = await searchFor('goreng cendana');
  assert.deepEqual(titles.sort(), ['Kuey Teow Goreng', 'Mee Goreng Mamak']);
  assert.deepEqual((await searchFor('goreng xyz')).titles, []);
});

test('the stall name and category are searched', async () => {
  assert.deepEqual((await searchFor('kak ina')).titles, ['Ayam Penyet']);
  assert.deepEqual((await searchFor('desserts')).titles, ['Bubur Cha Cha']);
});

test('the vendor location is searched like the stall name', async () => {
  const docs = [
    doc('Nasi Ayam', { vendorProfile: { stallName: 'Warung Pak Din', address: 'Arked Meranti, UTM Skudai' } }),
    doc('Teh Tarik', { category: 'Drinks', vendorProfile: { stallName: 'Kafe Cendana', address: 'Cafeteria B, UTM Skudai' } }),
  ];
  assert.deepEqual((await searchFor('arked meranti', docs)).titles, ['Nasi Ayam']);
  assert.deepEqual((await searchFor('meranti nasi', docs)).titles, ['Nasi Ayam']);
  assert.deepEqual((await searchFor('skudai', docs)).titles.length, 2);
});

test('the description matches whole words only', async () => {
  assert.deepEqual((await searchFor('egg')).titles, ['Mee Goreng Mamak']);
  assert.deepEqual((await searchFor('nut')).titles, [], 'coconut is not the word nut');
  assert.deepEqual((await searchFor('coconut')).titles.sort(), ['Bubur Cha Cha', 'Nasi Lemak Ayam']);
  assert.deepEqual((await searchFor('tem')).titles, [], 'tempeh is only in a description');
});

test('the best match comes first', async () => {
  const { titles } = await searchFor('ayam');
  assert.deepEqual(titles, ['Ayam Goreng Rice', 'Ayam Penyet', 'Nasi Lemak Ayam']);

  const goreng = (await searchFor('goreng')).titles;
  assert.equal(goreng.at(-1), 'Nasigoreng Special', 'inside a word scores below a word start');

  const rice = (await searchFor('rice')).titles;
  assert.equal(rice[0], 'Ayam Goreng Rice', 'a name match beats category and description matches');
});

test('a name starting with the whole search gets a bonus', async () => {
  const docs = [doc('Chicken Chop', { createdAt: 1 }), doc('Crispy Chicken Chop', { createdAt: 2 })];
  assert.deepEqual((await searchFor('chicken ch', docs)).titles, ['Chicken Chop', 'Crispy Chicken Chop']);
});

test('ties are newest first, and the server sorts by score then date', async () => {
  const docs = [doc('Nasi Ayam', { createdAt: 1 }), doc('Nasi Kerabu', { createdAt: 2 })];
  const { titles, pipeline } = await searchFor('nasi', docs);
  assert.deepEqual(titles, ['Nasi Kerabu', 'Nasi Ayam']);
  assert.deepEqual(stage(pipeline, '$sort'), { _score: -1, createdAt: -1, _id: -1 });
});

test('symbols are treated as plain text', async () => {
  const docs = [doc('Teh C (Ice)'), doc('Teh O')];
  assert.deepEqual((await searchFor('(ice)', docs)).titles, ['Teh C (Ice)']);
  assert.deepEqual((await searchFor('.*', docs)).titles, []);
});

test('search pages 20 at a time and only page 1 adds other stalls', async () => {
  const token = signedInAs(makeUser('customer'));
  const aggregate = mock.method(Listing, 'aggregate', async () =>
    Array.from({ length: 21 }, (_, index) => ({ _id: String(index), category: 'Rice' }))
  );

  const first = await call('/api/listings/search?q=nasi', token);
  assert.equal(first.body.listings.length, 20);
  assert.equal(first.body.hasMore, true);
  assert.ok(Array.isArray(first.body.otherStalls));
  assert.equal(stage(aggregate.mock.calls[0].arguments[0], '$limit'), 21);

  const calls = aggregate.mock.callCount();
  const third = await call('/api/listings/search?q=nasi&page=3', token);
  assert.equal(stage(aggregate.mock.calls[calls].arguments[0], '$skip'), 40);
  assert.equal(third.body.otherStalls, undefined);
  assert.equal(aggregate.mock.callCount(), calls + 1);
});

test('other stalls use the top 3 results\' categories, skip matched stalls and put low stock first', async () => {
  const token = signedInAs(makeUser('customer'));
  const results = [
    { category: 'Rice', stallName: 'Warung Pak Din' },
    { category: 'Noodles', stallName: 'Warung Pak Din' },
    { category: 'Rice', stallName: 'Warung Pak Din' },
    { category: 'Drinks', stallName: 'Warung Pak Din' },
  ];
  const calls = [];
  mock.method(Listing, 'aggregate', async (pipeline) => {
    calls.push(pipeline);
    if (calls.length === 1) return results;
    if (calls.length === 2) return [{ vendors: ['v1', 'v2'] }];
    return [{ _id: 'other', title: 'Nasi Goreng Kampung' }];
  });

  const res = await call('/api/listings/search?q=pak%20din', token);

  assert.deepEqual(res.body.otherStalls, [{ _id: 'other', title: 'Nasi Goreng Kampung' }]);
  assert.deepEqual(stage(calls[1], '$group'), { _id: null, vendors: { $addToSet: '$vendor' } });
  const match = calls[2][0].$match;
  assert.deepEqual(match.category.$in, ['Rice', 'Noodles']);
  assert.deepEqual(match.vendor.$nin, ['v1', 'v2']);
  assert.equal(match.status, 'active');
  assert.equal(match.quantityAvailable.$gt, 0);
  assert.deepEqual(stage(calls[2], '$sort'), { quantityAvailable: 1, pickupEnd: 1, _id: 1 });
  assert.equal(stage(calls[2], '$limit'), 6);
  assert.equal(stage(calls[2], '$project').stallName, '$vendorProfile.stallName');
  assert.equal(stage(calls[2], '$project').pickupAddress, '$vendorProfile.address');
});

test('other stalls only show when the search names a stall', async () => {
  const token = signedInAs(makeUser('customer'));
  const results = [{ category: 'Rice', stallName: 'Warung Pak Din' }, { category: 'Rice', stallName: 'Kafe Cendana' }];
  const aggregate = mock.method(Listing, 'aggregate', async () => results);

  for (const query of ['sambal', 'a', 'pa']) {
    const before = aggregate.mock.callCount();
    const res = await call(`/api/listings/search?q=${query}`, token);
    assert.deepEqual(res.body.otherStalls, [], query);
    assert.equal(aggregate.mock.callCount(), before + 1, query);
  }

  const before = aggregate.mock.callCount();
  await call('/api/listings/search?q=nasi%20cendana', token);
  assert.equal(aggregate.mock.callCount(), before + 3, 'a stall word of 3 or more letters counts');
});

test('no results means no other stalls and no extra queries', async () => {
  const token = signedInAs(makeUser('customer'));
  const aggregate = mock.method(Listing, 'aggregate', async () => []);

  const res = await call('/api/listings/search?q=zzz', token);

  assert.deepEqual(res.body, { listings: [], hasMore: false, otherStalls: [] });
  assert.equal(aggregate.mock.callCount(), 1);
});
