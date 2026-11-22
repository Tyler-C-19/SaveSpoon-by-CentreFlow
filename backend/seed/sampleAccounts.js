const point = (lng, lat) => ({ type: 'Point', coordinates: [lng, lat] });

// Every seeded vendor and customer, in seed order. `stall` is the vendor's profile.
const SAMPLE_ACCOUNTS = [
  {
    user: { name: 'Pak Din', email: 'vendor1@savespoon.test', phone: '012-3456781', role: 'vendor' },
    stall: {
      stallName: 'Warung Pak Din', description: 'Nasi campur and home-style dishes',
      address: 'Cafeteria A, UTM Skudai', phone: '012-3456781', location: point(103.6385, 1.5590), verified: true,
    },
  },
  {
    user: { name: 'Cendana Owner', email: 'vendor2@savespoon.test', phone: '012-3456782', role: 'vendor' },
    stall: {
      stallName: 'Kafe Cendana', description: 'Mamak-style noodles and roti',
      address: 'Cafeteria B, UTM Skudai', phone: '012-3456782', location: point(103.6410, 1.5565), verified: true,
    },
  },
  {
    user: { name: 'Kak Ina', email: 'vendor3@savespoon.test', phone: '012-3456783', role: 'vendor' },
    stall: {
      stallName: 'Roti Bakar Kak Ina', description: 'Toast, sandwiches and kuih',
      address: 'Kiosk near Library, UTM Skudai', phone: '012-3456783', location: point(103.6372, 1.5578), verified: false,
    },
  },
  { user: { name: 'Customer One', email: 'customer1@savespoon.test', phone: '012-3456784', role: 'customer' } },
  { user: { name: 'Customer Two', email: 'customer2@savespoon.test', phone: '012-3456785', role: 'customer' } },
];

// The sample accounts whose login email no longer exists, keeping their seed position.
function missingAccounts(existingEmails) {
  const existing = new Set(existingEmails.map((email) => email.toLowerCase()));
  return SAMPLE_ACCOUNTS
    .map((account, index) => ({ ...account, index }))
    .filter((account) => !existing.has(account.user.email));
}

// Sample vendors whose account exists but whose stall is gone, with the account to attach it to.
function missingStalls(users, stalls) {
  const withStall = new Set(stalls.map((stall) => String(stall.user)));
  return SAMPLE_ACCOUNTS
    .map((account, index) => ({ ...account, index }))
    .filter((account) => account.stall)
    .map((account) => ({ ...account, user: users.find((user) => user.email === account.user.email) }))
    .filter((account) => account.user && !withStall.has(String(account.user._id)))
    .map(({ stall, index, user }) => ({ stall, index, userId: user._id }));
}

module.exports = { SAMPLE_ACCOUNTS, missingAccounts, missingStalls, point };
