const express = require('express');
const notifications = require('../controllers/notificationController');
const { requireRole } = require('../middleware/auth');

const router = express.Router();

router.use(requireRole('customer', 'vendor'));
router.get('/', notifications.list);
router.delete('/', notifications.clearAll);
router.get('/unread-count', notifications.unreadCount);
router.post('/read-all', notifications.markAllRead);
router.post('/:id/read', notifications.markRead);
router.put('/devices', notifications.registerDevice);
router.delete('/devices', notifications.removeDevice);
router.delete('/:id', notifications.clearOne);
router.get('/preferences', notifications.getPrefs);
router.put('/preferences', notifications.updatePrefs);

module.exports = router;
