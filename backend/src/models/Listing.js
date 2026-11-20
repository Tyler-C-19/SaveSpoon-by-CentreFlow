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
    soldCount: { type: Number, default: 0, min: 0 },
    pickupStart: { type: Date, required: true },
    pickupEnd: { type: Date, required: true },
    allergens: { type: [{ type: String, enum: ALLERGENS }], default: [] },
    otherAllergens: { type: [{ type: String, trim: true }], default: [] },
    imageUrl: { type: String, default: null },
    // The photo: a smaller copy for cards, and the stored original with its framing for re-framing.
    imageThumbUrl: { type: String },
    imageId: { type: String },
    imageOriginalUrl: { type: String },
    imageWidth: { type: Number },
    imageHeight: { type: Number },
    imageCrop: { x: Number, y: Number, width: Number, height: Number },
    status: { type: String, enum: ['active', 'paused', 'sold_out', 'expired', 'cancelled'], default: 'active' },
    // When this round went on sale; relisting moves it forward. Older listings fall back to createdAt.
    listedAt: { type: Date, default: Date.now },
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
