const express = require('express');
const orders = require('../controllers/orderController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.post('/', requireRole('customer'), orders.createOrder);

module.exports = router;
