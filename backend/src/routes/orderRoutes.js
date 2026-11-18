const express = require('express');
const orders = require('../controllers/orderController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.post('/', requireRole('customer'), orders.createOrder);
router.get('/', requireRole('customer'), orders.listOrders);
router.get('/again', requireRole('customer'), orders.getOrderAgain);
router.get('/:id', requireRole('customer'), orders.getOrder);

module.exports = router;
