const REQUEST_ID_PATTERN = /^[A-Za-z0-9-]{8,64}$/;
const MAX_QUANTITY = 999;

const QUANTITY_ERROR = 'Choose a valid quantity.';
const REQUEST_ID_ERROR = 'This request is missing its ID.';

const isQuantity = (value) => Number.isInteger(value) && value >= 1 && value <= MAX_QUANTITY;

const isRequestId = (value) => typeof value === 'string' && REQUEST_ID_PATTERN.test(value);

module.exports = { isQuantity, isRequestId, QUANTITY_ERROR, REQUEST_ID_ERROR };
