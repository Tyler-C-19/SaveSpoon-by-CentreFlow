const orderService = require('../services/orderService');
const {
  isQuantity,
  isRequestId,
  QUANTITY_ERROR,
  REQUEST_ID_ERROR,
} = require('../validators/orderValidators');

const PLACE_FAILED = "We couldn't place your order. Please try again.";

async function createOrder(req, res) {
  const { listingId, quantity, requestId } = req.body ?? {};
  if (!isQuantity(quantity)) return res.status(400).json({ error: QUANTITY_ERROR });
  if (!isRequestId(requestId)) return res.status(400).json({ error: REQUEST_ID_ERROR });

  let result;
  try {
    result = await orderService.placeOrder({
      customer: req.user._id,
      listingId,
      quantity,
      requestId,
    });
  } catch (err) {
    console.error('Placing an order failed:', err.message);
    return res.status(500).json({ error: PLACE_FAILED });
  }

  if (result.problem) {
    const { status, ...problem } = result.problem;
    return res.status(status).json(problem);
  }
  return res.status(result.repeated ? 200 : 201).json({ order: result.order });
}

const PAGE_SIZE = 20;
const PAGE_PATTERN = /^[1-9]\d{0,4}$/;
const ORDER_NOT_FOUND = "We couldn't find this order.";

async function listOrders(req, res) {
  const { tab = 'all', page = '1' } = req.query;
  if (typeof tab !== 'string' || !orderService.ORDER_TABS.includes(tab)) {
    return res.status(400).json({ error: 'Choose All, Upcoming or History.' });
  }
  if (typeof page !== 'string' || !PAGE_PATTERN.test(page)) {
    return res.status(400).json({ error: 'Page must be a whole number.' });
  }

  const result = await orderService.listOrders({
    customer: req.user._id,
    tab,
    page: Number(page),
    pageSize: PAGE_SIZE,
  });
  return res.json(result);
}

async function getOrder(req, res) {
  const order = await orderService.findOwnOrder(req.user._id, req.params.id);
  if (!order) return res.status(404).json({ error: ORDER_NOT_FOUND });
  return res.json({ order });
}

async function getOrderAgain(req, res) {
  const listings = await orderService.orderAgainListings(req.user._id);
  return res.json({ listings });
}

module.exports = { createOrder, listOrders, getOrder, getOrderAgain, PLACE_FAILED, ORDER_NOT_FOUND, PAGE_SIZE };
