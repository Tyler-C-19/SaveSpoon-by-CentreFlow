enum NotificationType {
  newOrder('new_order'),
  orderCancelled('order_cancelled'),
  itemChanged('item_changed'),
  pickupReminder('pickup_reminder'),
  favouriteBack('favourite_back'),
  stockLow('stock_low'),
  other('');

  const NotificationType(this.value);

  final String value;

  static NotificationType from(String? value) => NotificationType.values
      .firstWhere((type) => type.value == value, orElse: () => other);
}

// Where a notification leads when it is tapped.
class NotificationLink {
  const NotificationLink({required this.type, this.orderId, this.listingId});

  factory NotificationLink.fromData(Map<String, dynamic> data) =>
      NotificationLink(
        type: NotificationType.from(data['type'] as String?),
        orderId: _text(data['orderId']),
        listingId: _text(data['listingId']),
      );

  final NotificationType type;
  final String? orderId;
  final String? listingId;

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.orderId,
    this.listingId,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['_id'] as String,
        type: NotificationType.from(json['type'] as String?),
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        orderId: json['orderId'] as String?,
        listingId: json['listingId'] as String?,
        readAt: _date(json['readAt']),
        createdAt: _date(json['createdAt']) ?? DateTime.now(),
      );

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final String? orderId;
  final String? listingId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  NotificationLink get link =>
      NotificationLink(type: type, orderId: orderId, listingId: listingId);

  AppNotification markedRead(DateTime when) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    orderId: orderId,
    listingId: listingId,
    readAt: readAt ?? when,
    createdAt: createdAt,
  );

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;
}

// The My Profile switches. Each role only has its own.
class NotificationPrefs {
  const NotificationPrefs(this.values);

  factory NotificationPrefs.fromJson(Map<String, dynamic> json) =>
      NotificationPrefs({
        for (final entry in json.entries)
          if (entry.value is bool) entry.key: entry.value as bool,
      });

  static const String orderAlerts = 'orderAlerts';
  static const String stockAlerts = 'stockAlerts';
  static const String itemChanges = 'itemChanges';
  static const String pickupReminders = 'pickupReminders';
  static const String favourites = 'favourites';

  final Map<String, bool> values;

  bool isOn(String key) => values[key] ?? true;

  NotificationPrefs withValue(String key, bool on) =>
      NotificationPrefs({...values, key: on});

  bool sameAs(NotificationPrefs other) =>
      values.length == other.values.length &&
      values.entries.every((entry) => other.values[entry.key] == entry.value);
}
