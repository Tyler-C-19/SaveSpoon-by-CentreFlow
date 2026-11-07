const express = require('express');
const vendors = require('../controllers/vendorController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.use(requireRole('vendor'));
router.get('/me', vendors.getMine);
router.post('/me', vendors.createMine);
router.patch('/me', vendors.updateMine);

module.exports = router;
