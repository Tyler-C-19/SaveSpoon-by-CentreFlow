const mongoose = require('mongoose');

const MAX_FAVOURITES = 200;

const favouriteSchema = new mongoose.Schema(
  {
    customer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    listing: { type: mongoose.Schema.Types.ObjectId, ref: 'Listing', required: true },
  },
  { timestamps: { createdAt: true, updatedAt: false } }
);

favouriteSchema.index({ customer: 1, listing: 1 }, { unique: true });
favouriteSchema.index({ listing: 1 });

module.exports = mongoose.model('Favourite', favouriteSchema);
module.exports.MAX_FAVOURITES = MAX_FAVOURITES;
