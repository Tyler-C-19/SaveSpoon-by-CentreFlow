const mongoose = require('mongoose');
const { CATEGORIES } = require('./listingOptions');

const ORDER_STATUSES = ['pending', 'confirmed', 'completed', 'cancelled'];
const CANCELLED_BY = ['customer', 'vendor'];
const CANCEL_REASONS = ['changed_mind', 'ordered_by_mistake', 'cannot_make_pickup', 'other'];

const orderSchema = new mongoose.Schema(
  {
    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    vendor: { type: mongoose.Schema.Types.ObjectId, ref: 'Vendor', required: true },
    listing: { type: mongoose.Schema.Types.ObjectId, ref: 'Listing', required: true },
    requestId: { type: String, required: true },
    checkoutId: { type: String },
    itemName: { type: String, required: true },
    category: { type: String, enum: CATEGORIES },
    imageThumbUrl: { type: String },
    stallName: { type: String, required: true },
    pickupAddress: { type: String },
    pickupStart: { type: Date, required: true },
    pickupEnd: { type: Date, required: true },
    quantity: { type: Number, required: true, min: 1 },
    unitPrice: { type: Number, required: true, min: 0 },
    originalUnitPrice: { type: Number, required: true, min: 0 },
    totalPrice: { type: Number, required: true, min: 0 },
    status: { type: String, enum: ORDER_STATUSES, default: 'pending' },
    cancelledAt: { type: Date },
    cancelledBy: { type: String, enum: CANCELLED_BY },
    cancelReason: { type: String, enum: CANCEL_REASONS },
  },
  { timestamps: true }
);

orderSchema.index({ customer: 1, requestId: 1 }, { unique: true });
orderSchema.index({ customer: 1, checkoutId: 1 });
orderSchema.index({ customer: 1, createdAt: -1 });
orderSchema.index({ vendor: 1, createdAt: -1 });
orderSchema.index({ customer: 1, cancelledAt: -1 });

module.exports = mongoose.model('Order', orderSchema);
module.exports.CANCEL_REASONS = CANCEL_REASONS;
