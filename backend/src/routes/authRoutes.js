const express = require('express');
const auth = require('../controllers/authController');
const { requireAuth } = require('../middleware/auth');
const { emailRateLimit, createEmailRateLimit } = require('../middleware/emailRateLimit');

const router = express.Router();

// Same limit as the email routes, with its own count.
const loginRateLimit = createEmailRateLimit();

router.post('/register', emailRateLimit, auth.register);
router.post('/verify-email', auth.verifyEmail);
router.post('/resend-verification', emailRateLimit, auth.resendVerification);
router.post('/login', loginRateLimit, auth.login);
router.post('/forgot-password', emailRateLimit, auth.forgotPassword);
router.post('/reset-password', auth.resetPassword);
router.post('/google', auth.googleSignIn);
router.post('/google/complete', auth.completeGoogleSignUp);
router.get('/me', requireAuth, auth.me);

module.exports = router;
