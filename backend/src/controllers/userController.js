const bcrypt = require('bcryptjs');
const passwordGuard = require('../services/passwordGuard');
const User = require('../models/User');
const Vendor = require('../models/Vendor');
const otpService = require('../services/otpService');
const emailService = require('../services/emailService');
const { signToken } = require('../services/tokenService');
const { normaliseEmail, emailError, codeError, isText } = require('../validators/authValidators');
const { detailsError, newPasswordError } = require('../validators/userValidators');

const OTP_FIELDS = '+otpHash +otpPurpose +otpExpiresAt +otpAttempts';
const BAD_CODE = 'That code is wrong or has expired. Request a new one.';
const EMAIL_TAKEN = 'An account with this email already exists.';

async function profileJson(user) {
  const json = user.toJSON();
  const guard = await User.findById(user._id).select('+passwordHash +passwordLockedUntil');
  json.hasPassword = Boolean(guard?.passwordHash);
  json.isGoogleLinked = Boolean(user.googleId);
  const lockedUntil = guard?.passwordLockedUntil;
  if (lockedUntil && lockedUntil.getTime() > Date.now()) json.lockedUntil = lockedUntil;
  if (user.role === 'vendor') {
    const vendor = await Vendor.findOne({ user: user._id });
    json.hasVendorProfile = Boolean(vendor);
    json.vendor = vendor;
  }
  return json;
}

async function sendQuietly(label, send) {
  try {
    await send();
    return true;
  } catch (err) {
    console.error(`Could not send ${label} email:`, err.message);
    return false;
  }
}

async function getMe(req, res) {
  res.json({ user: await profileJson(req.user) });
}

async function updateMe(req, res) {
  const invalid = detailsError(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const { name, phone } = req.body;
  if (name !== undefined) req.user.name = name.trim();
  if (phone !== undefined) req.user.phone = phone.trim();
  await req.user.save();
  return res.json({ user: await profileJson(req.user) });
}

async function changePassword(req, res) {
  const { currentPassword, newPassword } = req.body ?? {};
  const invalid = newPasswordError(currentPassword, newPassword);
  if (invalid) return res.status(400).json({ error: invalid });

  const user = await User.findById(req.user._id).select(passwordGuard.GUARD_FIELDS);
  if (!user.passwordHash) {
    return res.status(400).json({ error: 'This account signs in with Google and has no password.' });
  }
  const wrong = await passwordGuard.checkPassword(user, currentPassword);
  if (wrong) return res.status(wrong.status).json(wrong.body);
  if (await bcrypt.compare(newPassword, user.passwordHash)) {
    return res.status(400).json({ error: 'Choose a password different from your current one.' });
  }

  user.passwordHash = await bcrypt.hash(newPassword, 10);
  // Whole seconds, to match the token's issued-at time.
  user.passwordChangedAt = new Date(Math.floor(Date.now() / 1000) * 1000);
  await user.save();

  await sendQuietly('password changed', () => emailService.sendPasswordChangedEmail(user.email, user.name));
  return res.json({ token: signToken(user.id), message: 'Password changed.' });
}

async function requestEmailChange(req, res) {
  const { newEmail, currentPassword } = req.body ?? {};
  const user = await User.findById(req.user._id).select(`${passwordGuard.GUARD_FIELDS} +pendingEmail ${OTP_FIELDS}`);

  if (user.googleId || !user.passwordHash) {
    return res.status(400).json({
      error: "This account is linked to Google, so its email can't be changed.",
      code: 'GOOGLE_LINKED',
    });
  }
  const invalid = emailError(newEmail);
  if (invalid) return res.status(400).json({ error: invalid });
  if (!isText(currentPassword) || !currentPassword) {
    return res.status(400).json({ error: 'Enter your current password.' });
  }

  const email = normaliseEmail(newEmail);
  if (email === user.email) return res.status(400).json({ error: 'That is already your email.' });
  const wrong = await passwordGuard.checkPassword(user, currentPassword);
  if (wrong) return res.status(wrong.status).json(wrong.body);
  if (await User.exists({ email })) return res.status(409).json({ error: EMAIL_TAKEN });
  if (!otpService.canSendNewCode(user)) {
    return res.status(429).json({ error: 'A code was sent less than a minute ago. Wait a moment, then try again.' });
  }

  user.pendingEmail = email;
  const code = await otpService.issueCode(user, 'change_email');
  await user.save();
  const emailSent = await sendQuietly('email change code', () =>
    emailService.sendOtpEmail(email, user.name, code, 'change_email'));
  return res.json({ pendingEmail: email, emailSent });
}

async function resendEmailChange(req, res) {
  const user = await User.findById(req.user._id).select(`+pendingEmail ${OTP_FIELDS}`);
  if (!user.pendingEmail) return res.status(400).json({ error: 'Start the email change again.' });

  if (otpService.canSendNewCode(user)) {
    const code = await otpService.issueCode(user, 'change_email');
    await user.save();
    await sendQuietly('email change code', () =>
      emailService.sendOtpEmail(user.pendingEmail, user.name, code, 'change_email'));
  }
  return res.json({ message: 'A new code is on its way.' });
}

async function cancelEmailChange(req, res) {
  const user = await User.findById(req.user._id).select(`+pendingEmail ${OTP_FIELDS}`);
  if (user.pendingEmail || user.otpPurpose === 'change_email') {
    user.pendingEmail = undefined;
    if (user.otpPurpose === 'change_email') otpService.clearCode(user);
    await user.save();
  }
  return res.json({ user: await profileJson(user) });
}

async function verifyEmailChange(req, res) {
  const invalid = codeError(req.body?.code);
  if (invalid) return res.status(400).json({ error: invalid });

  const user = await User.findById(req.user._id).select(`+pendingEmail ${OTP_FIELDS}`);
  if (!user.pendingEmail) return res.status(400).json({ error: BAD_CODE });

  const correct = await otpService.checkCode(user, 'change_email', req.body.code);
  if (!correct) {
    await user.save();
    return res.status(400).json({ error: BAD_CODE });
  }

  const oldEmail = user.email;
  const newEmail = user.pendingEmail;
  otpService.clearCode(user);
  user.pendingEmail = undefined;

  if (await User.exists({ email: newEmail })) {
    await user.save();
    return res.status(409).json({ error: EMAIL_TAKEN });
  }

  user.email = newEmail;
  try {
    await user.save();
  } catch (err) {
    if (err.code === 11000) return res.status(409).json({ error: EMAIL_TAKEN });
    throw err;
  }

  await sendQuietly('email changed', () => emailService.sendEmailChangedEmail(oldEmail, user.name, newEmail));
  return res.json({ user: await profileJson(user) });
}

module.exports = {
  getMe, updateMe, changePassword, requestEmailChange, resendEmailChange, cancelEmailChange, verifyEmailChange,
  profileJson,
};
