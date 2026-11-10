const Vendor = require('../models/Vendor');
const Listing = require('../models/Listing');
const accountService = require('../services/accountService');
const { vendorProfileError, descriptionError } = require('../validators/vendorValidators');

const NO_PROFILE = { error: 'Set up your business profile first.', code: 'NO_VENDOR_PROFILE' };

async function getMine(req, res) {
  const vendor = await Vendor.findOne({ user: req.user._id });
  if (!vendor) return res.status(404).json(NO_PROFILE);
  return res.json({ vendor });
}

async function createMine(req, res) {
  const invalid = vendorProfileError(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const { stallName, phone, address, description, location, placeId } = req.body;
  try {
    const vendor = await Vendor.create({
      user: req.user._id,
      stallName: stallName.trim(),
      phone: phone.trim(),
      address: address.trim(),
      description: description?.trim(),
      location: { type: 'Point', coordinates: location.coordinates },
      placeId,
    });
    return res.status(201).json({ vendor });
  } catch (err) {
    if (err.code === 11000) {
      return res.status(409).json({ error: 'You already have a business profile.' });
    }
    throw err;
  }
}

async function updateMine(req, res) {
  const description = req.body?.description;
  const invalid = descriptionError(description);
  if (invalid) return res.status(400).json({ error: invalid });

  const vendor = await Vendor.findOneAndUpdate(
    { user: req.user._id },
    { description: description?.trim() ?? '' },
    { returnDocument: 'after' }
  );
  if (!vendor) return res.status(404).json(NO_PROFILE);
  return res.json({ vendor });
}

const samePin = (a = [], b = []) => a[0] === b[0] && a[1] === b[1];

async function replaceMine(req, res) {
  const invalid = vendorProfileError(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const vendor = await Vendor.findOne({ user: req.user._id });
  if (!vendor) return res.status(404).json(NO_PROFILE);

  const { stallName, phone, address, description, location, placeId } = req.body;
  const pinMoved = !samePin(vendor.location?.coordinates, location.coordinates);
  const addressChanged = vendor.address !== address.trim();

  if (pinMoved || addressChanged) {
    const activeOrders = await accountService.countActiveOrders({ vendor: vendor._id });
    if (activeOrders) {
      return res.status(409).json({
        error: `You have ${activeOrders} active order${activeOrders === 1 ? '' : 's'}. `
          + 'You can change your pickup location once pickup has ended for all of them.',
        code: 'ACTIVE_ORDERS',
      });
    }
  }

  const set = {
    stallName: stallName.trim(),
    phone: phone.trim(),
    address: address.trim(),
    description: description?.trim() ?? '',
  };
  const unset = {};
  const newLocation = { type: 'Point', coordinates: location.coordinates };
  if (pinMoved) set.location = newLocation;
  // A pin that came from anywhere but a suggestion has no place ID.
  if (placeId !== undefined) set.placeId = placeId;
  else if (pinMoved) unset.placeId = 1;

  const updated = await Vendor.findOneAndUpdate(
    { _id: vendor._id },
    { $set: set, ...(Object.keys(unset).length ? { $unset: unset } : {}) },
    { returnDocument: 'after' }
  );

  let listingsUpdated = 0;
  if (pinMoved) {
    const result = await Listing.updateMany({ vendor: vendor._id }, { location: newLocation });
    listingsUpdated = result?.modifiedCount ?? 0;
  }
  return res.json({ vendor: updated, listingsUpdated });
}

module.exports = { getMine, createMine, updateMine, replaceMine, NO_PROFILE };
