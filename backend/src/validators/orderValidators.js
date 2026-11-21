const { CANCEL_REASONS } = require('../models/Order');

const REQUEST_ID_PATTERN = /^[A-Za-z0-9-]{8,64}$/;
const MAX_QUANTITY = 999;

const QUANTITY_ERROR = 'Choose a valid quantity.';
const REQUEST_ID_ERROR = 'This request is missing its ID.';

const isQuantity = (value) => Number.isInteger(value) && value >= 1 && value <= MAX_QUANTITY;

const isRequestId = (value) => typeof value === 'string' && REQUEST_ID_PATTERN.test(value);

const CANCEL_REASON_ERROR = 'Choose one of the listed reasons, or none.';
const WHOLE_CHECKOUT_ERROR = 'wholeCheckout must be true or false.';

const isCancelReason = (value) => value == null || CANCEL_REASONS.includes(value);

const isOptionalFlag = (value) => value == null || typeof value === 'boolean';

module.exports = {
  isQuantity,
  isRequestId,
  isCancelReason,
  isOptionalFlag,
  QUANTITY_ERROR,
  REQUEST_ID_ERROR,
  CANCEL_REASON_ERROR,
  WHOLE_CHECKOUT_ERROR,
};
