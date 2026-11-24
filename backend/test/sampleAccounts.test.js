// Checks the sample account data and the restore choice; nothing touches the shared database.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');

const { SAMPLE_ACCOUNTS, missingAccounts, missingStalls } = require('../seed/sampleAccounts');
const { sampleListings, STALL_NAMES } = require('../seed/sampleListings');

test('the sample accounts are 3 vendors with stalls and 2 customers', () => {
  assert.deepEqual(SAMPLE_ACCOUNTS.map(({ user }) => user.role), ['vendor', 'vendor', 'vendor', 'customer', 'customer']);
  assert.deepEqual(SAMPLE_ACCOUNTS.filter(({ stall }) => stall).map(({ stall }) => stall.stallName), STALL_NAMES);
  for (const { stall } of SAMPLE_ACCOUNTS.filter((account) => account.stall)) {
    const [lng, lat] = stall.location.coordinates;
    assert.ok(lng > 100 && lat < 2, 'stored as [lng, lat]');
  }
});

test('only accounts whose email is gone are restored, keeping their seed position', () => {
  const emails = SAMPLE_ACCOUNTS.map(({ user }) => user.email);
  assert.deepEqual(missingAccounts(emails), []);

  const missing = missingAccounts(emails.filter((email) => email !== 'vendor2@savespoon.test'));
  assert.deepEqual(missing.map(({ user, index }) => [user.email, index]), [['vendor2@savespoon.test', 1]]);
  assert.equal(missing[0].stall.stallName, 'Kafe Cendana');

  assert.equal(missingAccounts(['VENDOR1@savespoon.test']).length, 4);
});

test('a restored stall gets only its own sample listings', () => {
  const restored = { _id: new mongoose.Types.ObjectId(), location: SAMPLE_ACCOUNTS[1].stall.location };
  const listings = sampleListings([{ _id: null }, restored, { _id: null }]).filter((listing) => listing.vendor);
  assert.ok(listings.length > 0);
  assert.ok(listings.every((listing) => listing.vendor === restored._id));
});

test('a sample vendor whose stall is gone gets it back on the same account', () => {
  const users = SAMPLE_ACCOUNTS.map(({ user }) => ({ _id: new mongoose.Types.ObjectId(), email: user.email }));
  const stalls = [users[0], users[2]].map((user) => ({ user: user._id }));

  const missing = missingStalls(users, stalls);

  assert.deepEqual(missing.map(({ stall, index }) => [stall.stallName, index]), [['Kafe Cendana', 1]]);
  assert.equal(String(missing[0].userId), String(users[1]._id));
  assert.deepEqual(missingStalls(users, users.slice(0, 3).map((user) => ({ user: user._id }))), []);
  assert.deepEqual(missingStalls(users.slice(3), []), []);
});
