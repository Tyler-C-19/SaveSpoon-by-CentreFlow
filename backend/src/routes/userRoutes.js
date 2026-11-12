const express = require('express');
const users = require('../controllers/userController');
const photos = require('../controllers/photoController');
const account = require('../controllers/accountController');
const { requireRole } = require('../middleware/auth');
const { photoUpload } = require('../middleware/photoUpload');

const router = express.Router();

router.use(requireRole('customer', 'vendor'));
router.get('/me', users.getMe);
router.patch('/me', users.updateMe);
router.delete('/me', account.deleteMe);
router.get('/me/summary', account.getSummary);
router.post('/me/password', users.changePassword);
router.post('/me/email', users.requestEmailChange);
router.post('/me/email/resend', users.resendEmailChange);
router.post('/me/email/verify', users.verifyEmailChange);
router.delete('/me/email', users.cancelEmailChange);
router.put('/me/photo', photoUpload, photos.setPhoto);
router.patch('/me/photo', photos.reframePhoto);
router.delete('/me/photo', photos.removePhoto);

module.exports = router;
