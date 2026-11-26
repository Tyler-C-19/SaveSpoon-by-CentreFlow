const mongoose = require('mongoose');

const NOTIFICATION_TYPES = ['new_order', 'order_cancelled', 'item_changed', 'pickup_reminder', 'favourite_back', 'stock_low'];
const KEEP_DAYS = 30;

const notificationSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    type: { type: String, enum: NOTIFICATION_TYPES, required: true },
    title: { type: String, required: true },
    body: { type: String, required: true },
    // What a tap opens.
    orderId: { type: String },
    listingId: { type: String },
    readAt: { type: Date },
    // Cleared ones are hidden but kept until they expire, so a cleared pickup
    // reminder isn't added again.
    clearedAt: { type: Date },
    // Stops the same pickup reminder or stock alert being added twice.
    key: { type: String },
  },
  { timestamps: { createdAt: true, updatedAt: false } }
);

notificationSchema.index({ user: 1, createdAt: -1 });
notificationSchema.index({ createdAt: 1 }, { expireAfterSeconds: KEEP_DAYS * 24 * 60 * 60 });
notificationSchema.index(
  { user: 1, key: 1 },
  { unique: true, partialFilterExpression: { key: { $type: 'string' } } }
);

module.exports = mongoose.model('Notification', notificationSchema);
module.exports.NOTIFICATION_TYPES = NOTIFICATION_TYPES;
module.exports.KEEP_DAYS = KEEP_DAYS;
