// These tests check the seed's sample data in memory and never connect to the shared database.
const { test } = require('node:test');
const assert = require('node:assert/strict');

const Listing = require('../src/models/Listing');
const { sampleSearchListings, sampleRefreshOps } = require('../seed/sampleSearchListings');

test('search samples are valid listings spread across all three stalls', () => {
  const ids = [1, 2, 3].map(() => new Listing()._id);
  const stalls = ids.map((id) => ({ _id: id, location: { type: 'Point', coordinates: [103.6, 1.5] } }));
  const samples = sampleSearchListings(stalls);

  assert.equal(samples.length, 9);
  assert.deepEqual([...new Set(samples.map((item) => item.vendor))], ids);
  for (const sample of samples) {
    const listing = new Listing({ ...sample, pickupStart: new Date(), pickupEnd: new Date(Date.now() + 3600000) });
    assert.equal(listing.validateSync(), undefined, sample.title);
  }
  assert.ok(!samples.some((item) => /eggplant/i.test(item.description)));
});

test('refreshing samples restocks and reopens them without touching other fields', () => {
  const now = Date.UTC(2026, 10, 7, 4);
  const [op] = sampleRefreshOps(
    [{ vendor: 'v1', title: 'Teh Tarik', quantityAvailable: 12, soldCount: 2, pickupStart: 'old', pickupEnd: 'old', category: 'Drinks' }],
    now
  );

  assert.deepEqual(op.updateOne.filter, { vendor: 'v1', title: 'Teh Tarik' });
  assert.equal(op.updateOne.upsert, true);
  const { $set, $setOnInsert } = op.updateOne.update;
  assert.equal($set.pickupStart.getTime(), now + 3600000);
  assert.equal($set.pickupEnd.getTime(), now + 8 * 3600000);
  assert.equal($set.quantityAvailable, 12);
  assert.equal($set.status, 'active');
  assert.deepEqual($setOnInsert, { vendor: 'v1', title: 'Teh Tarik', soldCount: 2, category: 'Drinks' });
});

