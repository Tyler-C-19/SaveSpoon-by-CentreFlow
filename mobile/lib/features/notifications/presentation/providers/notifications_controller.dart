import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../core/network/api_client.dart';
import '../../../orders/data/order_repository.dart';
import '../../../orders/domain/order.dart';
import '../../data/notification_repository.dart';
import '../../data/push_platform.dart';
import '../../domain/app_notification.dart';
import '../../domain/pickup_reminders.dart';

const _ordersChanged = 'orders_changed';
// Logging out shouldn't wait long on a slow server.
const _removeTimeout = Duration(seconds: 5);
const _reminderPages = 3;

class NotificationsController extends ChangeNotifier
    with WidgetsBindingObserver {
  NotificationsController({
    required this.platform,
    required this.repository,
    required this.orders,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PushPlatform platform;
  final NotificationRepository repository;
  final OrderRepository orders;
  final DateTime Function() _clock;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Future<bool>? _starting;
  String? _role;
  String? _token;
  int _unreadCount = 0;
  bool _permitted = true;
  NotificationLink? _pending;
  bool _disposed = false;

  int get unreadCount => _unreadCount;

  // False when notifications are turned off for SaveSpoon on this phone.
  bool get permitted => _permitted;

  String? get role => _role;

  // A tapped notification waiting for the tab shell to open it.
  NotificationLink? get pendingLink => _pending;

  NotificationLink? takePendingLink() {
    final link = _pending;
    _pending = null;
    return link;
  }

  Future<void> signedIn(String role) async {
    _role = role;
    final hasFirebase = await (_starting ??= _start());
    if (_role != role) return;
    _permitted = await platform.isPermitted();
    _notify();
    if (hasFirebase) await _registerToken();
    unawaited(refreshUnread());
    if (role == 'customer') unawaited(syncReminders());
    final launch = await platform.launchMessage();
    if (launch != null) _queueOpen(launch);
  }

  // Runs before the session is cleared, while the server still knows who
  // this is.
  Future<void> beforeSignOut() async {
    final token = _token;
    _role = null;
    _token = null;
    _unreadCount = 0;
    _pending = null;
    _notify();
    await platform.clearReminders();
    if (token == null) return;
    try {
      await repository.removeDevice(token).timeout(_removeTimeout);
    } on Object catch (e) {
      debugPrint('Device not removed: $e');
    }
  }

  Future<bool> _start() async {
    WidgetsBinding.instance.addObserver(this);
    final hasFirebase = await platform.start();
    _subscriptions
      ..add(platform.received.listen(_onReceived))
      ..add(platform.opened.listen(_queueOpen))
      ..add(platform.tokenRefreshes.listen((token) => _registerToken(token)));
    return hasFirebase;
  }

  Future<void> _registerToken([String? fresh]) async {
    if (_role == null) return;
    final token = fresh ?? await platform.token();
    if (token == null) return;
    try {
      await repository.registerDevice(token);
      _token = token;
    } on ApiException catch (e) {
      debugPrint('Device not registered: ${e.message}');
    }
  }

  Future<void> refreshUnread() async {
    if (_role == null) return;
    try {
      _unreadCount = await repository.fetchUnreadCount();
      _notify();
    } on ApiException {
      return;
    }
  }

  void setUnreadCount(int count) {
    _unreadCount = count;
    _notify();
  }

  // Reschedules the phone's pickup reminders from the open orders.
  Future<void> syncReminders() async {
    if (_role != 'customer') return;
    try {
      final prefs = await repository.fetchPrefs();
      if (!prefs.isOn(NotificationPrefs.pickupReminders)) {
        await platform.clearReminders();
        return;
      }
      final upcoming = <Order>[];
      for (var page = 1; page <= _reminderPages; page++) {
        final result = await orders.fetchOrders(
          tab: OrderTab.upcoming,
          page: page,
        );
        upcoming.addAll(result.orders);
        if (!result.hasMore) break;
      }
      if (_role != 'customer') return;
      await platform.replaceReminders(planReminders(upcoming, _clock()));
    } on ApiException catch (e) {
      debugPrint('Reminders not updated: ${e.message}');
    }
  }

  // Asks for Android's notification permission once per phone.
  Future<void> askOnce() async {
    if (await platform.wasAsked()) return;
    await platform.markAsked();
    _permitted = await platform.requestPermission();
    _notify();
  }

  Future<bool> turnOn() async {
    _permitted = await platform.requestPermission();
    _notify();
    return _permitted;
  }

  // After Android stops asking, notifications can only be turned on in the
  // phone's Settings. The app checks again when it comes back.
  Future<void> openSettings() => platform.openSettings();

  Future<void> _onReceived(PushMessage message) async {
    if (message.type == _ordersChanged) {
      await syncReminders();
      return;
    }
    await platform.show(message);
    await refreshUnread();
  }

  void _queueOpen(PushMessage message) {
    final id = message.data['notificationId'];
    if (id is String && id.isNotEmpty) {
      unawaited(
        repository.markRead(id).then((_) => refreshUnread(), onError: (_) {}),
      );
    }
    final link = NotificationLink.fromData(message.data);
    if (link.type == NotificationType.other) return;
    _pending = link;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _role == null) return;
    unawaited(_onResume());
  }

  Future<void> _onResume() async {
    _permitted = await platform.isPermitted();
    _notify();
    await refreshUnread();
    await syncReminders();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_starting != null) WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
