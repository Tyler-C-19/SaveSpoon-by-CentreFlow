const mongoose = require('mongoose');

// One finished selling round of a listing, saved when the listing is relisted.
// Names and prices are copies, so the record still reads correctly after edits or deletion.
const salesRecordSchema = new mongoose.Schema(
  {
    listing: { type: mongoose.Schema.Types.ObjectId, ref: 'Listing', required: true },
    vendor: { type: mongoose.Schema.Types.ObjectId, ref: 'Vendor', required: true },
    stallName: { type: String, required: true },
    pickupAddress: { type: String },
    itemName: { type: String, required: true },
    category: { type: String },
    originalPrice: { type: Number, required: true },
    discountedPrice: { type: Number, required: true },
    pickupStart: { type: Date, required: true },
    pickupEnd: { type: Date, required: true },
    stockOffered: { type: Number, required: true, min: 0 },
    sold: { type: Number, required: true, min: 0 },
    leftover: { type: Number, required: true, min: 0 },
    recordedAt: { type: Date, default: Date.now },
  },
  { timestamps: true }
);

salesRecordSchema.index({ listing: 1, pickupEnd: -1 });
salesRecordSchema.index({ vendor: 1, pickupEnd: -1 });

module.exports = mongoose.model('SalesRecord', salesRecordSchema);
