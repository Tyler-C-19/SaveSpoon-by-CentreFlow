const mongoose = require('mongoose');

const SECRET_FIELDS = ['passwordHash', 'otpHash', 'otpPurpose', 'otpExpiresAt', 'otpAttempts'];

const userSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true },
    email: { type: String, required: true, unique: true, lowercase: true, trim: true },
    phone: { type: String, trim: true },
    passwordHash: { type: String, select: false },
    role: { type: String, enum: ['customer', 'vendor', 'admin'], default: 'customer' },
    googleId: { type: String, unique: true, sparse: true },
    emailVerified: { type: Boolean, default: false },
    otpHash: { type: String, select: false },
    otpPurpose: { type: String, enum: ['verify_email', 'reset_password'], select: false },
    otpExpiresAt: { type: Date, select: false },
    otpAttempts: { type: Number, default: 0, select: false },
  },
  {
    timestamps: true,
    toJSON: {
      transform(doc, ret) {
        SECRET_FIELDS.forEach((field) => delete ret[field]);
        return ret;
      },
    },
  }
);

module.exports = mongoose.model('User', userSchema);
