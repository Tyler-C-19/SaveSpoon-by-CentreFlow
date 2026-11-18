const express = require('express');
const listings = require('../controllers/listingController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.post('/', requireRole('vendor'), listings.createListing);
router.get('/', requireRole('customer'), listings.getAvailable);
router.get('/running-out', requireRole('customer'), listings.getRunningOut);
router.get('/search', requireRole('customer'), listings.search);
router.get('/mine', requireRole('vendor'), listings.getMine);
router.get('/mine/:id', requireRole('vendor'), listings.getMineOne);
router.patch('/:id/stock', requireRole('vendor'), listings.updateStock);
router.patch('/:id/availability', requireRole('vendor'), listings.updateAvailability);
router.post('/:id/relist', requireRole('vendor'), listings.relist);
router.patch('/:id', requireRole('vendor'), listings.updateListing);
router.delete('/:id', requireRole('vendor'), listings.deleteListing);
router.post('/allergen-suggestions', requireRole('vendor'), listings.suggestAllergens);
router.get('/:id', requireRole('customer'), listings.getDetails);

module.exports = router;
