const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_PATTERN = /^\+?[0-9][0-9\s-]{6,18}[0-9]$/;
const CODE_PATTERN = /^[0-9]{6}$/;
const SIGN_UP_ROLES = ['customer', 'vendor'];
const MAX_PASSWORD_BYTES = 72; // bcrypt limit

const isText = (value) => typeof value === 'string';

function normaliseEmail(value) {
  return isText(value) ? value.trim().toLowerCase() : '';
}

function passwordError(password) {
  if (!isText(password)) return 'Enter a password.';
  if (password.length < 8) return 'Password must be at least 8 characters.';
  if (Buffer.byteLength(password, 'utf8') > MAX_PASSWORD_BYTES) {
    return 'Password must be 72 characters or fewer.';
  }
  if (!/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
    return 'Password must include at least one letter and one number.';
  }
  return null;
}

function emailError(email) {
  return EMAIL_PATTERN.test(normaliseEmail(email)) ? null : 'Enter a valid email address.';
}

function codeError(code) {
  return isText(code) && CODE_PATTERN.test(code) ? null : 'Enter the 6-digit code.';
}

function registrationError(body = {}) {
  const { name, email, phone, password, role, acceptedTerms } = body;
  if (!SIGN_UP_ROLES.includes(role)) return 'Choose Customer or Vendor.';
  if (!isText(name) || !name.trim() || name.trim().length > 100) return 'Enter your full name.';
  const invalidEmail = emailError(email);
  if (invalidEmail) return invalidEmail;
  if (!isText(phone) || !PHONE_PATTERN.test(phone.trim())) return 'Enter a valid phone number.';
  const invalidPassword = passwordError(password);
  if (invalidPassword) return invalidPassword;
  if (acceptedTerms !== true) return 'Accept the Terms and Privacy Policy to continue.';
  return null;
}

function googleProfileError(body = {}) {
  const { role, phone, acceptedTerms } = body;
  if (!SIGN_UP_ROLES.includes(role)) return 'Choose Customer or Vendor.';
  if (!isText(phone) || !PHONE_PATTERN.test(phone.trim())) return 'Enter a valid phone number.';
  if (acceptedTerms !== true) return 'Accept the Terms and Privacy Policy to continue.';
  return null;
}

module.exports = {
  normaliseEmail, passwordError, emailError, codeError, registrationError, googleProfileError, isText, PHONE_PATTERN,
};
