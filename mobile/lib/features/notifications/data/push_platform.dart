import 'dart:async';

import '../domain/pickup_reminders.dart';

class PushMessage {
  const PushMessage({required this.data, this.title, this.body});

  final Map<String, dynamic> data;
  final String? title;
  final String? body;

  String? get type => data['type'] as String?;
}

// The phone's side of notifications: Firebase pushes, shown notifications and
// scheduled pickup reminders. Tests and phones without Firebase use [NoPush].
abstract class PushPlatform {
  // False when Firebase isn't set up; reminders still work.
  Future<bool> start();

  Future<String?> token();

  Stream<String> get tokenRefreshes;

  // Messages that arrive while the app is open.
  Stream<PushMessage> get received;

  // Notifications the user tapped.
  Stream<PushMessage> get opened;

  // The tap that launched the app, if one did.
  Future<PushMessage?> launchMessage();

  Future<void> show(PushMessage message);

  Future<bool> isPermitted();

  Future<bool> requestPermission();

  // Opens SaveSpoon's page in the phone's Settings.
  Future<void> openSettings();

  Future<bool> wasAsked();

  Future<void> markAsked();

  Future<void> replaceReminders(List<PickupReminder> reminders);

  Future<void> clearReminders();
}

class NoPush implements PushPlatform {
  const NoPush();

  @override
  Future<bool> start() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<PushMessage> get received => const Stream.empty();

  @override
  Stream<PushMessage> get opened => const Stream.empty();

  @override
  Future<PushMessage?> launchMessage() async => null;

  @override
  Future<void> show(PushMessage message) async {}

  @override
  Future<bool> isPermitted() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> openSettings() async {}

  @override
  Future<bool> wasAsked() async => true;

  @override
  Future<void> markAsked() async {}

  @override
  Future<void> replaceReminders(List<PickupReminder> reminders) async {}

  @override
  Future<void> clearReminders() async {}
}
