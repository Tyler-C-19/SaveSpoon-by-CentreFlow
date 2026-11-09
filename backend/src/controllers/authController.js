const bcrypt = require('bcryptjs');
const User = require('../models/User');
const otpService = require('../services/otpService');
const emailService = require('../services/emailService');
const googleService = require('../services/googleService');
const { signToken } = require('../services/tokenService');
const {
  normaliseEmail, passwordError, emailError, codeError, registrationError, googleProfileError, isText,
} = require('../validators/authValidators');

const OTP_FIELDS = '+otpHash +otpPurpose +otpExpiresAt +otpAttempts';
const BAD_CODE = 'That code is wrong or has expired. Request a new one.';
const BAD_LOGIN = 'Incorrect email or password.';
// Dummy hash so unknown emails take the same time.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', 10);

async function sendCode(user, purpose) {
  const code = await otpService.issueCode(user, purpose);
  await user.save();
  try {
    await emailService.sendOtpEmail(user.email, user.name, code, purpose);
    return true;
  } catch (err) {
    console.error('Could not send email:', err.message);
    return false;
  }
}

function findWithOtp(email) {
  return User.findOne({ email }).select(OTP_FIELDS);
}

function sendSession(res, user, status = 200) {
  if (user.role === 'admin') {
    return res.status(403).json({
      error: "Admin accounts can't use the mobile app. Use the admin dashboard.",
      code: 'ADMIN_USE_DASHBOARD',
    });
  }
  return res.status(status).json({ token: signToken(user.id), user });
}

async function register(req, res) {
  const invalid = registrationError(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const email = normaliseEmail(req.body.email);
  if (await User.findOne({ email })) {
    return res.status(409).json({ error: 'An account with this email already exists.' });
  }

  const user = new User({
    name: req.body.name.trim(),
    email,
    phone: req.body.phone.trim(),
    role: req.body.role,
    passwordHash: await bcrypt.hash(req.body.password, 10),
  });

  let emailSent;
  try {
    emailSent = await sendCode(user, 'verify_email');
  } catch (err) {
    if (err.code === 11000) {
      return res.status(409).json({ error: 'An account with this email already exists.' });
    }
    throw err;
  }

  return res.status(201).json({ email, emailSent });
}

async function verifyEmail(req, res) {
  const invalid = emailError(req.body?.email) || codeError(req.body?.code);
  if (invalid) return res.status(400).json({ error: invalid });

  const user = await findWithOtp(normaliseEmail(req.body.email));
  if (!user) return res.status(400).json({ error: BAD_CODE });

  const correct = await otpService.checkCode(user, 'verify_email', req.body.code);
  if (!correct) {
    await user.save();
    return res.status(400).json({ error: BAD_CODE });
  }

  otpService.clearCode(user);
  user.emailVerified = true;
  await user.save();
  return sendSession(res, user);
}

async function resendVerification(req, res) {
  const invalid = emailError(req.body?.email);
  if (invalid) return res.status(400).json({ error: invalid });

  const user = await findWithOtp(normaliseEmail(req.body.email));
  if (user && !user.emailVerified && otpService.canSendNewCode(user)) {
    await sendCode(user, 'verify_email');
  }
  return res.json({ message: 'If that account needs verifying, a new code is on its way.' });
}

async function login(req, res) {
  const { email: rawEmail, password } = req.body ?? {};
  if (!isText(rawEmail) || !isText(password) || !rawEmail || !password) {
    return res.status(400).json({ error: 'Enter your email and password.' });
  }

  const email = normaliseEmail(rawEmail);
  const user = await User.findOne({ email }).select(`+passwordHash ${OTP_FIELDS}`);
  const correct = await bcrypt.compare(password, user?.passwordHash ?? DUMMY_HASH);
  if (!user || !user.passwordHash || !correct) {
    return res.status(401).json({ error: BAD_LOGIN });
  }

  if (user.role === 'admin') return sendSession(res, user);

  if (!user.emailVerified) {
    if (otpService.canSendNewCode(user)) await sendCode(user, 'verify_email');
    return res.status(403).json({
      error: 'Verify your email to continue.',
      code: 'EMAIL_NOT_VERIFIED',
      email,
    });
  }

  return sendSession(res, user);
}

async function forgotPassword(req, res) {
  const invalid = emailError(req.body?.email);
  if (invalid) return res.status(400).json({ error: invalid });

  const user = await findWithOtp(normaliseEmail(req.body.email));
  if (user && otpService.canSendNewCode(user)) {
    await sendCode(user, 'reset_password');
  }
  return res.json({ message: 'If that email has an account, a reset code is on its way.' });
}

async function resetPassword(req, res) {
  const { email, code, newPassword } = req.body ?? {};
  const invalid = emailError(email) || codeError(code) || passwordError(newPassword);
  if (invalid) return res.status(400).json({ error: invalid });

  const user = await findWithOtp(normaliseEmail(email));
  if (!user) return res.status(400).json({ error: BAD_CODE });

  const correct = await otpService.checkCode(user, 'reset_password', code);
  if (!correct) {
    await user.save();
    return res.status(400).json({ error: BAD_CODE });
  }

  otpService.clearCode(user);
  user.passwordHash = await bcrypt.hash(newPassword, 10);
  user.emailVerified = true;
  await user.save();
  return res.json({ message: 'Password updated. Log in with your new password.' });
}

async function readGoogleProfile(idToken) {
  if (!isText(idToken) || !idToken) return null;
  try {
    const profile = await googleService.verifyGoogleToken(idToken);
    return profile.emailVerified && profile.email ? profile : null;
  } catch (err) {
    console.error('Google token rejected:', err.message);
    return null;
  }
}

async function findAndLinkGoogleUser(profile) {
  const email = normaliseEmail(profile.email);
  const user = await User.findOne({ googleId: profile.googleId }) ?? await User.findOne({ email }).select('+passwordHash');
  if (!user) return null;
  if (user.role === 'admin') return user;

  if (user.googleId !== profile.googleId || !user.emailVerified) {
    // Unverified account: drop its password once Google confirms the email.
    if (!user.emailVerified) user.passwordHash = undefined;
    user.googleId = profile.googleId;
    user.emailVerified = true;
    await user.save();
  }
  return user;
}

async function googleSignIn(req, res) {
  const profile = await readGoogleProfile(req.body?.idToken);
  if (!profile) return res.status(401).json({ error: 'Google sign-in failed. Try again.' });

  const user = await findAndLinkGoogleUser(profile);
  if (user) return sendSession(res, user);

  return res.json({
    needsProfile: true,
    email: normaliseEmail(profile.email),
    name: profile.name ?? '',
  });
}

async function completeGoogleSignUp(req, res) {
  const invalid = googleProfileError(req.body);
  if (invalid) return res.status(400).json({ error: invalid });

  const profile = await readGoogleProfile(req.body.idToken);
  if (!profile) return res.status(401).json({ error: 'Google sign-in failed. Try again.' });

  const existing = await findAndLinkGoogleUser(profile);
  if (existing) return sendSession(res, existing);

  const email = normaliseEmail(profile.email);
  const user = new User({
    name: profile.name?.trim() || email.split('@')[0],
    email,
    phone: req.body.phone.trim(),
    role: req.body.role,
    googleId: profile.googleId,
    emailVerified: true,
  });
  try {
    await user.save();
  } catch (err) {
    if (err.code === 11000) {
      return res.status(409).json({ error: 'An account with this email already exists.' });
    }
    throw err;
  }
  return sendSession(res, user, 201);
}

function me(req, res) {
  res.json({ user: req.user });
}

module.exports = {
  register, verifyEmail, resendVerification, login, forgotPassword, resetPassword, googleSignIn, completeGoogleSignUp, me,
};
