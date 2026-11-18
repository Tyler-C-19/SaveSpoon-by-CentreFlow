// Checks the sample sales records without connecting to the shared database.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const SalesRecord = require('../src/models/SalesRecord');
const { sampleListings } = require('../seed/sampleListings');
const { sampleSalesRecords, SAMPLE_ROUNDS } = require('../seed/sampleSalesRecords');

const stalls = ['Warung Pak Din', 'Kafe Cendana', 'Roti Bakar Kak Ina'].map((stallName, index) => ({
  _id: new mongoose.Types.ObjectId(),
  stallName,
  address: `Cafeteria ${index + 1}, UTM Skudai`,
  location: { type: 'Point', coordinates: [103.6385, 1.559] },
}));
const listings = sampleListings(stalls).map((fields) => ({ _id: new mongoose.Types.ObjectId(), ...fields }));

test('each sample round becomes a valid sales record for an earlier day', () => {
  const records = sampleSalesRecords(listings, stalls);
  assert.equal(records.length, SAMPLE_ROUNDS.length);
  for (const record of records) {
    const listing = listings.find((item) => String(item._id) === String(record.listing));
    const stall = stalls.find((item) => String(item._id) === String(record.vendor));
    assert.equal(record.itemName, listing.title);
    assert.equal(record.stallName, stall.stallName);
    assert.equal(record.pickupAddress, stall.address);
    assert.equal(record.stockOffered, record.sold + record.leftover);
    assert.ok(record.pickupEnd < new Date(), 'earlier rounds have ended');
    assert.equal(new SalesRecord(record).validateSync(), undefined);
  }
});
