const mongoose = require('mongoose');

const SECRET_FIELDS = [
  'passwordHash', 'otpHash', 'otpPurpose', 'otpExpiresAt', 'otpAttempts', 'pendingEmail', 'passwordChangedAt', 'photoId',
  'passwordAttempts', 'passwordLockedUntil', 'photoWidth', 'photoHeight',
];

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
    otpPurpose: { type: String, enum: ['verify_email', 'reset_password', 'change_email'], select: false },
    otpExpiresAt: { type: Date, select: false },
    otpAttempts: { type: Number, default: 0, select: false },
    pendingEmail: { type: String, lowercase: true, trim: true, select: false },
    // Tokens issued before this time are rejected.
    passwordChangedAt: { type: Date },
    // Wrong password tries on profile actions, and the lock after too many.
    passwordAttempts: { type: Number, default: 0, select: false },
    passwordLockedUntil: { type: Date, select: false },
    // photoUrl is the framed square shown everywhere; the original is kept so the
    // pic can be framed again. photoCrop holds fractions of the original.
    photoUrl: { type: String },
    photoId: { type: String },
    photoOriginalUrl: { type: String },
    photoWidth: { type: Number },
    photoHeight: { type: Number },
    photoCrop: {
      x: { type: Number },
      y: { type: Number },
      width: { type: Number },
      height: { type: Number },
    },
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
