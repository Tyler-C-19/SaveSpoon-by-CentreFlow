const express = require('express');
const listings = require('../controllers/listingController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.post('/', requireRole('vendor'), listings.createListing);
router.get('/mine', requireRole('vendor'), listings.getMine);
router.post('/allergen-suggestions', requireRole('vendor'), listings.suggestAllergens);

module.exports = router;
