const passwordGuard = require('../services/passwordGuard');
const User = require('../models/User');
const Vendor = require('../models/Vendor');
const Listing = require('../models/Listing');
const Cart = require('../models/Cart');
const accountService = require('../services/accountService');
const { removeQuietly } = require('./photoController');
const { isText } = require('../validators/authValidators');

const plural = (count, word) => `${count} ${word}${count === 1 ? '' : 's'}`;

async function summaryFor(user) {
  if (user.role !== 'vendor') {
    return {
      listingCount: 0,
      activeListingCount: 0,
      activeOrderCount: await accountService.countActiveOrders({ customer: user._id }),
    };
  }
  const vendor = await Vendor.findOne({ user: user._id });
  if (!vendor) return { vendor: null, listingCount: 0, activeListingCount: 0, activeOrderCount: 0 };
  const [listingCount, activeListingCount, activeOrderCount] = await Promise.all([
    accountService.countListings(vendor._id),
    accountService.countActiveListings(vendor._id),
    accountService.countActiveOrders({ vendor: vendor._id }),
  ]);
  return { vendor, listingCount, activeListingCount, activeOrderCount };
}

function blockedMessage({ activeListingCount, activeOrderCount }) {
  const parts = [];
  if (activeListingCount) parts.push(plural(activeListingCount, 'active listing'));
  if (activeOrderCount) parts.push(plural(activeOrderCount, 'active order'));
  if (!parts.length) return null;
  return `You have ${parts.join(' and ')}. You can delete your account once pickup has ended for all of them.`;
}

async function getSummary(req, res) {
  const { listingCount, activeListingCount, activeOrderCount } = await summaryFor(req.user);
  res.json({ listingCount, activeListingCount, activeOrderCount });
}

async function deleteMe(req, res) {
  const { password, confirm } = req.body ?? {};
  const user = await User.findById(req.user._id).select(passwordGuard.GUARD_FIELDS);

  if (user.passwordHash) {
    if (!isText(password) || !password) return res.status(400).json({ error: 'Enter your password.' });
    const wrong = await passwordGuard.checkPassword(user, password);
    if (wrong) return res.status(wrong.status).json(wrong.body);
  } else if (confirm !== 'DELETE') {
    return res.status(400).json({ error: 'Type DELETE to confirm.' });
  }

  const summary = await summaryFor(user);
  const blocked = blockedMessage(summary);
  if (blocked) {
    return res.status(409).json({
      error: blocked,
      code: 'ACCOUNT_DELETE_BLOCKED',
      activeListingCount: summary.activeListingCount,
      activeOrderCount: summary.activeOrderCount,
    });
  }

  // The user goes last, so a failure part-way leaves an account that can try again.
  if (summary.vendor) {
    await Listing.deleteMany({ vendor: summary.vendor._id });
    await Vendor.deleteOne({ _id: summary.vendor._id });
  }
  await Cart.deleteOne({ customer: user._id });
  await User.deleteOne({ _id: user._id });
  if (user.photoId) await removeQuietly(user.photoId);

  return res.json({ message: 'Your account has been deleted.' });
}

module.exports = { getSummary, deleteMe, blockedMessage };
