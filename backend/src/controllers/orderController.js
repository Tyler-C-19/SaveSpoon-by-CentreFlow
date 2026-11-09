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

module.exports = { createOrder, PLACE_FAILED };
