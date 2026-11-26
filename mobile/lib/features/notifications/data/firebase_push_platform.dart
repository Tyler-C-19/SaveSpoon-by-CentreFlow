import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/theme/app_theme.dart';
import '../domain/pickup_reminders.dart';
import 'push_platform.dart';

const _ordersChannel = AndroidNotificationChannel(
  'orders',
  'Orders',
  description: 'New orders, cancellations and item changes',
  importance: Importance.high,
);

const _remindersChannel = AndroidNotificationChannel(
  'reminders',
  'Pickup Reminders',
  description: 'A reminder before pickup starts',
  importance: Importance.high,
);

const _askedKey = 'notifications_asked';
const _reminderType = 'pickup_reminder';
const _icon = 'ic_stat_savespoon';

class FirebasePushPlatform implements PushPlatform {
  FirebasePushPlatform({
    FlutterLocalNotificationsPlugin? local,
    FlutterSecureStorage? storage,
  }) : _local = local ?? FlutterLocalNotificationsPlugin(),
       _storage = storage ?? const FlutterSecureStorage();

  final FlutterLocalNotificationsPlugin _local;
  final FlutterSecureStorage _storage;
  final _opened = StreamController<PushMessage>.broadcast();
  FirebaseMessaging? _messaging;
  PushMessage? _localLaunch;

  AndroidFlutterLocalNotificationsPlugin? get _android => _local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> start() async {
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      ),
      onDidReceiveNotificationResponse: (response) {
        final message = _decode(response.payload);
        if (message != null) _opened.add(message);
      },
    );
    await _android?.createNotificationChannel(_ordersChannel);
    await _android?.createNotificationChannel(_remindersChannel);
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _localLaunch = _decode(launch!.notificationResponse?.payload);
    }

    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _opened.add(_fromRemote(message)),
      );
      return true;
    } catch (e) {
      // No google-services.json in this build.
      debugPrint('Push notifications are off: $e');
      return false;
    }
  }

  // The backend's Firebase Admin SDK sends to registration tokens, so the
  // newer installation ID registration isn't used yet.
  @override
  Future<String?> token() async {
    try {
      // ignore: deprecated_member_use
      return await _messaging?.getToken();
    } catch (e) {
      debugPrint('No push token: $e');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes =>
      // ignore: deprecated_member_use
      _messaging?.onTokenRefresh ?? const Stream.empty();

  @override
  Stream<PushMessage> get received => _messaging == null
      ? const Stream.empty()
      : FirebaseMessaging.onMessage.map(_fromRemote);

  @override
  Stream<PushMessage> get opened => _opened.stream;

  @override
  Future<PushMessage?> launchMessage() async {
    final remote = await _messaging?.getInitialMessage();
    if (remote != null) return _fromRemote(remote);
    final local = _localLaunch;
    _localLaunch = null;
    return local;
  }

  // Android doesn't show pushes while the app is open, so they're shown here.
  @override
  Future<void> show(PushMessage message) => _local.show(
    id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
    title: message.title,
    body: message.body,
    notificationDetails: _details(
      message.type == _reminderType ? _remindersChannel : _ordersChannel,
    ),
    payload: jsonEncode(message.data),
  );

  @override
  Future<bool> isPermitted() async =>
      await _android?.areNotificationsEnabled() ?? true;

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  // The same Settings page the map uses for location.
  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<bool> wasAsked() async => await _storage.read(key: _askedKey) == 'yes';

  @override
  Future<void> markAsked() => _storage.write(key: _askedKey, value: 'yes');

  @override
  Future<void> replaceReminders(List<PickupReminder> reminders) async {
    await clearReminders();
    for (final reminder in reminders) {
      await _local.zonedSchedule(
        id: reminder.id,
        scheduledDate: tz.TZDateTime.from(reminder.at, tz.UTC),
        notificationDetails: _details(_remindersChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: reminder.title,
        body: reminder.body,
        payload: jsonEncode({
          'type': _reminderType,
          'orderId': reminder.orderId,
        }),
      );
    }
  }

  // Only scheduled reminders, so notifications already showing stay.
  @override
  Future<void> clearReminders() async {
    for (final pending in await _local.pendingNotificationRequests()) {
      if (_decode(pending.payload)?.type == _reminderType) {
        await _local.cancel(id: pending.id);
      }
    }
  }

  NotificationDetails _details(AndroidNotificationChannel channel) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: _icon,
          color: AppColors.primary,
        ),
      );

  PushMessage _fromRemote(RemoteMessage message) => PushMessage(
    data: Map<String, dynamic>.from(message.data),
    title: message.notification?.title,
    body: message.notification?.body,
  );

  PushMessage? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final data = jsonDecode(payload);
      return data is Map<String, dynamic> ? PushMessage(data: data) : null;
    } on FormatException {
      return null;
    }
  }
}
