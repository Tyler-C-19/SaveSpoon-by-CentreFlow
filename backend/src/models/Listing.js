const mongoose = require('mongoose');
const { CATEGORIES, ALLERGENS } = require('./listingOptions');

const listingSchema = new mongoose.Schema(
  {
    vendor: { type: mongoose.Schema.Types.ObjectId, ref: 'Vendor', required: true },
    title: { type: String, required: true, trim: true },
    description: { type: String, trim: true },
    category: { type: String, enum: CATEGORIES, required: true },
    isHalal: { type: Boolean, required: true },
    originalPrice: { type: Number, required: true, min: 0 },
    discountedPrice: { type: Number, required: true, min: 0 },
    quantityAvailable: { type: Number, required: true, min: 0 },
    pickupStart: { type: Date, required: true },
    pickupEnd: { type: Date, required: true },
    allergens: { type: [{ type: String, enum: ALLERGENS }], default: [] },
    otherAllergens: { type: [{ type: String, trim: true }], default: [] },
    imageUrl: { type: String, default: null },
    status: { type: String, enum: ['active', 'sold_out', 'expired', 'cancelled'], default: 'active' },
    // Copied from the vendor when the listing is created, so "nearby" queries are simple
    location: {
      type: { type: String, enum: ['Point'], default: 'Point' },
      coordinates: { type: [Number], required: true },
    },
  },
  { timestamps: true }
);

listingSchema.index({ location: '2dsphere' });

module.exports = mongoose.model('Listing', listingSchema);
