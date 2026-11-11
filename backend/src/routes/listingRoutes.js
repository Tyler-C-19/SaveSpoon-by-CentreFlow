const express = require('express');
const listings = require('../controllers/listingController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.post('/', requireRole('vendor'), listings.createListing);
router.get('/', requireRole('customer'), listings.getAvailable);
router.get('/running-out', requireRole('customer'), listings.getRunningOut);
router.get('/mine', requireRole('vendor'), listings.getMine);
router.post('/allergen-suggestions', requireRole('vendor'), listings.suggestAllergens);
router.get('/:id', requireRole('customer'), listings.getDetails);

module.exports = router;
