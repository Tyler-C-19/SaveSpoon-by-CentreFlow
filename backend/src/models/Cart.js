const mongoose = require('mongoose');

const MAX_CART_ITEMS = 20;

const cartItemSchema = new mongoose.Schema(
  {
    listing: { type: mongoose.Schema.Types.ObjectId, ref: 'Listing', required: true },
    quantity: { type: Number, required: true, min: 1 },
    itemName: { type: String, required: true },
    stallName: { type: String, required: true },
    unitPriceWhenAdded: { type: Number, required: true, min: 0 },
  },
  { _id: false }
);

const cartSchema = new mongoose.Schema(
  {
    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, unique: true },
    items: {
      type: [cartItemSchema],
      default: [],
      validate: [(items) => items.length <= MAX_CART_ITEMS, 'Too many items in the cart'],
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('Cart', cartSchema);
module.exports.MAX_CART_ITEMS = MAX_CART_ITEMS;
