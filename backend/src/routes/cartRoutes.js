const express = require('express');
const cart = require('../controllers/cartController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.use(requireRole('customer'));
router.get('/', cart.getCart);
router.delete('/', cart.clearCart);
router.post('/items', cart.addItem);
router.patch('/items/:listingId', cart.updateItem);
router.delete('/items/:listingId', cart.removeItem);
router.delete('/unavailable', cart.removeUnavailable);
router.post('/checkout', cart.checkout);

module.exports = router;
