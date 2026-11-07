const path = require('path');
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const User = require('../src/models/User');
const { normaliseEmail, emailError, passwordError } = require('../src/validators/authValidators');

const DEFAULT_ADMIN = 'admin@savespoon.test';

function adminDetailsError({ email, password }) {
  if (normaliseEmail(email) === DEFAULT_ADMIN) return `ADMIN_EMAIL can't be ${DEFAULT_ADMIN}.`;
  const invalidEmail = emailError(email);
  if (invalidEmail) return `ADMIN_EMAIL: ${invalidEmail}`;
  const invalidPassword = passwordError(password);
  return invalidPassword ? `ADMIN_PASSWORD: ${invalidPassword}` : null;
}

async function removeDefaultAdmin() {
  const { deletedCount } = await User.deleteOne({ email: DEFAULT_ADMIN, role: 'admin' });
  return deletedCount > 0;
}

async function createAdmin({ email, password }) {
  const invalid = adminDetailsError({ email, password });
  if (invalid) throw new Error(invalid);

  const address = normaliseEmail(email);
  const existing = await User.findOne({ email: address });
  if (existing) {
    if (existing.role !== 'admin') throw new Error(`${address} already belongs to a ${existing.role} account.`);
    return false;
  }

  await User.create({
    name: 'SaveSpoon Admin',
    email: address,
    role: 'admin',
    passwordHash: await bcrypt.hash(password, 10),
    emailVerified: true,
  });
  return true;
}

async function run() {
  require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
  const details = { email: process.env.ADMIN_EMAIL, password: process.env.ADMIN_PASSWORD };
  const invalid = adminDetailsError(details);
  if (invalid) throw new Error(`Nothing changed. ${invalid}`);

  await mongoose.connect(process.env.MONGODB_URI);
  if (await removeDefaultAdmin()) console.log(`Removed ${DEFAULT_ADMIN}.`);

  const created = await createAdmin(details);
  console.log(created ? 'Admin account created.' : 'That admin already exists, so nothing changed.');
}

if (require.main === module) {
  run()
    .catch((err) => {
      console.error(err.message);
      process.exitCode = 1;
    })
    .finally(() => mongoose.disconnect());
}

module.exports = { createAdmin, removeDefaultAdmin, adminDetailsError, DEFAULT_ADMIN };
