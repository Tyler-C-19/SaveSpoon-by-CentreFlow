const Vendor = require('../models/Vendor');
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

module.exports = { getMine, createMine, updateMine, NO_PROFILE };
