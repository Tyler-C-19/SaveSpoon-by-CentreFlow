const express = require('express');
const favourites = require('../controllers/favouriteController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.use(requireRole('customer'));
router.get('/ids', favourites.getIds);
router.put('/:listingId', favourites.add);
router.delete('/:listingId', favourites.remove);

module.exports = router;
