const mongoose = require('mongoose');
const Notification = require('../models/Notification');
const User = require('../models/User');
const notifications = require('../services/notificationService');
const { isDeviceToken, prefsError, TOKEN_ERROR } = require('../validators/notificationValidators');

const LIST_SIZE = 50;
const LIST_FIELDS = 'type title body orderId listingId readAt createdAt';
const NOT_FOUND = { error: "We couldn't find this notification." };

const cutoff = (now = new Date()) => new Date(now.getTime() - Notification.KEEP_DAYS * 24 * 60 * 60 * 1000);

// Expired entries can linger until MongoDB's cleanup runs, so they're filtered out here too.
function inboxFilter(user, now) {
  return { user: user._id, clearedAt: null, createdAt: { $gt: cutoff(now) } };
}

async function addReminders(user, now) {
  if (user.role !== 'customer') return;
  try {
    await notifications.addDueReminders(user._id, now);
  } catch (err) {
    console.error('Adding pickup reminders failed:', err.message);
  }
}

async function list(req, res) {
  const now = new Date();
  await addReminders(req.user, now);
  const filter = inboxFilter(req.user, now);
  const [items, unreadCount] = await Promise.all([
    Notification.find(filter, LIST_FIELDS, { sort: { createdAt: -1, _id: -1 }, limit: LIST_SIZE, lean: true }),
    Notification.countDocuments({ ...filter, readAt: null }),
  ]);
  return res.json({ notifications: items, unreadCount });
}

async function unreadCount(req, res) {
  const now = new Date();
  await addReminders(req.user, now);
  const count = await Notification.countDocuments({ ...inboxFilter(req.user, now), readAt: null });
  return res.json({ unreadCount: count });
}

async function markRead(req, res) {
  if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json(NOT_FOUND);
  const note = await Notification.findOneAndUpdate(
    { _id: req.params.id, user: req.user._id },
    { $set: { readAt: new Date() } },
    { returnDocument: 'after', projection: LIST_FIELDS }
  );
  if (!note) return res.status(404).json(NOT_FOUND);
  return res.json({ notification: note });
}

async function markAllRead(req, res) {
  await Notification.updateMany({ user: req.user._id, readAt: null }, { $set: { readAt: new Date() } });
  return res.json({ unreadCount: 0 });
}

async function clearOne(req, res) {
  if (!mongoose.isValidObjectId(req.params.id)) return res.status(404).json(NOT_FOUND);
  const now = new Date();
  const result = await Notification.updateOne(
    { _id: req.params.id, user: req.user._id, clearedAt: null },
    { $set: { clearedAt: now }, $min: { readAt: now } }
  );
  if (!result.matchedCount) return res.status(404).json(NOT_FOUND);
  const count = await Notification.countDocuments({ ...inboxFilter(req.user, now), readAt: null });
  return res.json({ unreadCount: count });
}

async function clearAll(req, res) {
  const now = new Date();
  await Notification.updateMany(
    { user: req.user._id, clearedAt: null },
    { $set: { clearedAt: now }, $min: { readAt: now } }
  );
  return res.json({ unreadCount: 0 });
}

// A phone belongs to one account at a time, so its token leaves any other account.
async function registerDevice(req, res) {
  const { token } = req.body ?? {};
  if (!isDeviceToken(token)) return res.status(400).json({ error: TOKEN_ERROR });
  await User.updateMany({ _id: { $ne: req.user._id }, deviceTokens: token }, { $pull: { deviceTokens: token } });
  await User.updateOne({ _id: req.user._id }, { $pull: { deviceTokens: token } });
  await User.updateOne(
    { _id: req.user._id },
    { $push: { deviceTokens: { $each: [token], $slice: -User.MAX_DEVICES } } }
  );
  return res.json({ registered: true });
}

async function removeDevice(req, res) {
  const { token } = req.body ?? {};
  if (!isDeviceToken(token)) return res.status(400).json({ error: TOKEN_ERROR });
  await User.updateOne({ _id: req.user._id }, { $pull: { deviceTokens: token } });
  return res.json({ removed: true });
}

function prefsFor(user) {
  const saved = user.notificationPrefs ?? {};
  return Object.fromEntries(
    notifications.PREFS_BY_ROLE[user.role].map((key) => [key, saved[key] !== false])
  );
}

async function getPrefs(req, res) {
  return res.json({ prefs: prefsFor(req.user) });
}

async function updatePrefs(req, res) {
  const { prefs } = req.body ?? {};
  const invalid = prefsError(prefs, notifications.PREFS_BY_ROLE[req.user.role]);
  if (invalid) return res.status(400).json({ error: invalid });
  const changes = Object.fromEntries(Object.entries(prefs).map(([key, value]) => [`notificationPrefs.${key}`, value]));
  const user = await User.findOneAndUpdate({ _id: req.user._id }, { $set: changes }, { returnDocument: 'after' });
  return res.json({ prefs: prefsFor(user) });
}

module.exports = { list, unreadCount, markRead, markAllRead, clearOne, clearAll, registerDevice, removeDevice, getPrefs, updatePrefs };
