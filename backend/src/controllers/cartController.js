const Cart = require('../models/Cart');
const Order = require('../models/Order');
const Listing = require('../models/Listing');
const orderService = require('../services/orderService');
const { viewCart, findOrCreateCart } = require('../services/cartService');
const { PLACE_FAILED } = require('./orderController');
const {
  isQuantity,
  isRequestId,
  QUANTITY_ERROR,
  REQUEST_ID_ERROR,
} = require('../validators/orderValidators');

const { MAX_CART_ITEMS } = Cart;
const CART_CHANGED = 'CART_CHANGED';
const TOTAL_TOLERANCE = 0.005;

const sendProblem = (res, { status, ...problem }) => res.status(status).json(problem);

const sameListing = (item, listingId) => String(item.listing) === String(listingId);

async function sendCart(res, cart, message) {
  const { view } = await viewCart(cart);
  return res.json({ cart: view, ...(message ? { message } : {}) });
}

async function getCart(req, res) {
  return sendCart(res, await Cart.findOne({ customer: req.user._id }));
}

async function addItem(req, res) {
  const { listingId, quantity } = req.body ?? {};
  if (!isQuantity(quantity)) return res.status(400).json({ error: QUANTITY_ERROR });

  const { listing, vendor } = await orderService.findLiveListing(listingId);
  if (!listing) return sendProblem(res, orderService.GONE);
  const problem = orderService.unavailableProblem(listing);
  if (problem) return sendProblem(res, problem);

  const cart = await findOrCreateCart(req.user._id);
  const existing = cart.items.find((item) => sameListing(item, listing._id));
  if (!existing && cart.items.length >= MAX_CART_ITEMS) {
    return res.status(400).json({
      error: `Your cart is full (${MAX_CART_ITEMS} items). Remove something to add more.`,
    });
  }

  const wanted = quantity + (existing?.quantity ?? 0);
  const kept = Math.min(wanted, listing.quantityAvailable);
  if (existing) {
    existing.quantity = kept;
  } else {
    cart.items.push({
      listing: listing._id,
      quantity: kept,
      itemName: listing.title,
      stallName: vendor.stallName,
      unitPriceWhenAdded: listing.discountedPrice,
    });
  }
  await cart.save();

  const { title } = listing;
  let message = `Added ${quantity} x ${title} to your cart.`;
  if (kept < wanted) message = `Only ${kept} ${title} left, so your cart now has ${kept}.`;
  else if (existing) message = `Added ${quantity} more ${title}. Your cart now has ${kept}.`;
  return sendCart(res, cart, message);
}

async function updateItem(req, res) {
  const { quantity } = req.body ?? {};
  if (!isQuantity(quantity)) return res.status(400).json({ error: QUANTITY_ERROR });

  const cart = await Cart.findOne({ customer: req.user._id });
  const item = cart?.items.find((entry) => sameListing(entry, req.params.listingId));
  if (!item) return res.status(404).json({ error: "This item isn't in your cart." });

  item.quantity = quantity;
  await cart.save();
  return sendCart(res, cart);
}

async function removeItem(req, res) {
  const cart = await Cart.findOne({ customer: req.user._id });
  if (cart) {
    cart.items = cart.items.filter((item) => !sameListing(item, req.params.listingId));
    await cart.save();
  }
  return sendCart(res, cart);
}

async function removeUnavailable(req, res) {
  const cart = await Cart.findOne({ customer: req.user._id });
  if (cart) {
    const { entries } = await viewCart(cart);
    const live = new Set(entries.map(({ item }) => String(item.listing)));
    cart.items = cart.items.filter((item) => live.has(String(item.listing)));
    await cart.save();
  }
  return sendCart(res, cart);
}

async function clearCart(req, res) {
  const cart = await Cart.findOne({ customer: req.user._id });
  if (cart) {
    cart.items = [];
    await cart.save();
  }
  return sendCart(res, cart);
}

async function undoCheckout(customer, checkoutId, reserved) {
  await Order.deleteMany({ customer, checkoutId });
  await Promise.all(
    reserved.map(({ listing, quantity }) => orderService.releaseStock(listing._id, quantity))
  );
}

async function reserveAll(entries) {
  const reserved = [];
  for (const { item, listing, vendor } of entries) {
    const updated = await orderService.reserveStock(listing._id, item.quantity);
    if (!updated) return { reserved, failed: { item, listing } };
    reserved.push({ listing, vendor, quantity: item.quantity });
  }
  return { reserved };
}

async function checkoutFailure({ item, listing }) {
  const current = await Listing.findById(listing._id);
  const name = item.itemName;
  const ending = 'so nothing was ordered. Check your cart and try again.';
  const problem = orderService.unavailableProblem(current);
  if (problem?.code === orderService.SOLD_OUT) return `${name} just sold out, ${ending}`;
  if (problem?.code === orderService.PICKUP_ENDED) return `Pickup for ${name} has ended, ${ending}`;
  if (problem) return `${name} is no longer available, ${ending}`;
  return `Only ${current.quantityAvailable} ${name} left, ${ending}`;
}

async function checkout(req, res) {
  const { requestId, expectedTotal } = req.body ?? {};
  if (!isRequestId(requestId)) return res.status(400).json({ error: REQUEST_ID_ERROR });
  if (!Number.isFinite(expectedTotal)) {
    return res.status(400).json({ error: 'Your cart total is missing.' });
  }

  const customer = req.user._id;
  const earlier = await Order.find({ customer, checkoutId: requestId });
  if (earlier.length) return res.json({ orders: earlier });

  const cart = await Cart.findOne({ customer });
  const { view, entries } = await viewCart(cart);
  if (!entries.length) {
    return res.status(409).json({
      code: CART_CHANGED,
      error: 'None of the items in your cart can be ordered right now.',
    });
  }
  if (Math.abs(view.total - expectedTotal) > TOTAL_TOLERANCE) {
    return res.status(409).json({
      code: CART_CHANGED,
      error: `Your cart changed. The new total is RM ${view.total.toFixed(2)}. Check it and try again.`,
    });
  }

  const { reserved, failed } = await reserveAll(entries);
  if (failed) {
    await undoCheckout(customer, requestId, reserved);
    return res.status(409).json({
      code: CART_CHANGED,
      error: await checkoutFailure(failed),
    });
  }

  let orders;
  try {
    orders = await Order.insertMany(
      reserved.map(({ listing, vendor, quantity }) =>
        orderService.orderFields({
          customer,
          listing,
          vendor,
          quantity,
          checkoutId: requestId,
          requestId: `${requestId}:${listing._id}`,
        })
      )
    );
  } catch (err) {
    await undoCheckout(customer, requestId, reserved);
    console.error('Cart checkout failed:', err.message);
    return res.status(500).json({ error: PLACE_FAILED });
  }

  try {
    const placed = new Set(reserved.map(({ listing }) => String(listing._id)));
    cart.items = cart.items.filter((item) => !placed.has(String(item.listing)));
    await cart.save();
  } catch (err) {
    console.error('Emptying the cart failed:', err.message);
  }
  return res.status(201).json({ orders });
}

module.exports = {
  getCart,
  addItem,
  updateItem,
  removeItem,
  removeUnavailable,
  clearCart,
  checkout,
};
