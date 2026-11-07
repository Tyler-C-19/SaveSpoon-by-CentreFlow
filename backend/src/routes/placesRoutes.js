const express = require('express');
const places = require('../controllers/placesController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.use(requireRole('vendor'));
router.get('/suggestions', places.suggestions);
router.get('/:placeId/location', places.location);

module.exports = router;
