const mongoose = require('mongoose');
const { CATEGORIES } = require('./listingOptions');

const ORDER_STATUSES = ['pending', 'confirmed', 'completed', 'cancelled'];

const orderSchema = new mongoose.Schema(
  {
    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    vendor: { type: mongoose.Schema.Types.ObjectId, ref: 'Vendor', required: true },
    listing: { type: mongoose.Schema.Types.ObjectId, ref: 'Listing', required: true },
    requestId: { type: String, required: true },
    checkoutId: { type: String },
    itemName: { type: String, required: true },
    category: { type: String, enum: CATEGORIES },
    stallName: { type: String, required: true },
    pickupAddress: { type: String },
    pickupStart: { type: Date, required: true },
    pickupEnd: { type: Date, required: true },
    quantity: { type: Number, required: true, min: 1 },
    unitPrice: { type: Number, required: true, min: 0 },
    originalUnitPrice: { type: Number, required: true, min: 0 },
    totalPrice: { type: Number, required: true, min: 0 },
    status: { type: String, enum: ORDER_STATUSES, default: 'pending' },
  },
  { timestamps: true }
);

orderSchema.index({ customer: 1, requestId: 1 }, { unique: true });
orderSchema.index({ customer: 1, checkoutId: 1 });
orderSchema.index({ customer: 1, createdAt: -1 });
orderSchema.index({ vendor: 1, createdAt: -1 });

module.exports = mongoose.model('Order', orderSchema);
