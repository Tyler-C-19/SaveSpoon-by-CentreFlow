import '../../../core/network/api_client.dart';
import '../domain/app_notification.dart';

class NotificationInbox {
  const NotificationInbox({required this.items, required this.unreadCount});

  final List<AppNotification> items;
  final int unreadCount;
}

class NotificationRepository {
  NotificationRepository(this.api);

  final ApiClient api;

  Future<NotificationInbox> fetchInbox() async {
    final data = await api.get('/api/notifications');
    return NotificationInbox(
      items: [
        for (final item in data['notifications'] as List? ?? const [])
          AppNotification.fromJson(item as Map<String, dynamic>),
      ],
      unreadCount: data['unreadCount'] as int? ?? 0,
    );
  }

  Future<int> fetchUnreadCount() async {
    final data = await api.get('/api/notifications/unread-count');
    return data['unreadCount'] as int? ?? 0;
  }

  // The server reads a JSON object, so an empty one is sent.
  Future<void> markRead(String id) =>
      api.post('/api/notifications/$id/read', body: const {});

  // Returns the unread count left.
  Future<int> clear(String id) async {
    final data = await api.delete('/api/notifications/$id');
    return data['unreadCount'] as int? ?? 0;
  }

  Future<void> clearAll() => api.delete('/api/notifications');

  Future<void> markAllRead() =>
      api.post('/api/notifications/read-all', body: const {});

  Future<void> registerDevice(String token) =>
      api.put('/api/notifications/devices', body: {'token': token});

  Future<void> removeDevice(String token) =>
      api.delete('/api/notifications/devices', body: {'token': token});

  Future<NotificationPrefs> fetchPrefs() async {
    final data = await api.get('/api/notifications/preferences');
    return NotificationPrefs.fromJson(
      data['prefs'] as Map<String, dynamic>? ?? const {},
    );
  }

  Future<NotificationPrefs> savePrefs(NotificationPrefs prefs) async {
    final data = await api.put(
      '/api/notifications/preferences',
      body: {'prefs': prefs.values},
    );
    return NotificationPrefs.fromJson(
      data['prefs'] as Map<String, dynamic>? ?? const {},
    );
  }
}
