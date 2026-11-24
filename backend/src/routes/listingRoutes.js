const express = require('express');
const listings = require('../controllers/listingController');
const photos = require('../controllers/listingPhotoController');
const { requireRole } = require('../middleware/auth');
const { listingPhotoUpload } = require('../middleware/photoUpload');

const router = express.Router();

router.post('/', requireRole('vendor'), listings.createListing);
router.get('/', requireRole('customer'), listings.getAvailable);
router.get('/running-out', requireRole('customer'), listings.getRunningOut);
router.get('/favourites', requireRole('customer'), listings.getFavourites);
router.get('/search', requireRole('customer'), listings.search);
router.get('/mine', requireRole('vendor'), listings.getMine);
router.get('/mine/:id', requireRole('vendor'), listings.getMineOne);
router.patch('/:id/stock', requireRole('vendor'), listings.updateStock);
router.patch('/:id/availability', requireRole('vendor'), listings.updateAvailability);
router.post('/:id/relist', requireRole('vendor'), listings.relist);
router.put('/:id/photo', requireRole('vendor'), listingPhotoUpload, photos.setPhoto);
router.patch('/:id/photo', requireRole('vendor'), photos.reframePhoto);
router.delete('/:id/photo', requireRole('vendor'), photos.removePhoto);
router.patch('/:id', requireRole('vendor'), listings.updateListing);
router.delete('/:id', requireRole('vendor'), listings.deleteListing);
router.post('/allergen-suggestions', requireRole('vendor'), listings.suggestAllergens);
router.get('/:id/vendor', requireRole('customer'), listings.getVendorInfo);
router.get('/:id', requireRole('customer'), listings.getDetails);

module.exports = router;
