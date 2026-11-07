const express = require('express');
const auth = require('../controllers/authController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

router.post('/register', auth.register);
router.post('/verify-email', auth.verifyEmail);
router.post('/resend-verification', auth.resendVerification);
router.post('/login', auth.login);
router.post('/forgot-password', auth.forgotPassword);
router.post('/reset-password', auth.resetPassword);
router.post('/google', auth.googleSignIn);
router.post('/google/complete', auth.completeGoogleSignUp);
router.get('/me', requireAuth, auth.me);

module.exports = router;
