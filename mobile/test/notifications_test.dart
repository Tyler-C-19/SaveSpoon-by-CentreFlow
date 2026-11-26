import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/notifications/data/notification_repository.dart';
import 'package:savespoon/features/notifications/data/push_platform.dart';
import 'package:savespoon/features/notifications/domain/app_notification.dart';
import 'package:savespoon/features/notifications/domain/pickup_reminders.dart';
import 'package:savespoon/features/notifications/presentation/notification_links.dart';
import 'package:savespoon/features/notifications/presentation/pages/notification_settings_page.dart';
import 'package:savespoon/features/notifications/presentation/pages/notifications_page.dart';
import 'package:savespoon/features/notifications/presentation/providers/notifications_controller.dart';
import 'package:savespoon/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:savespoon/features/notifications/presentation/widgets/notification_settings_section.dart';
import 'package:savespoon/features/orders/data/order_repository.dart';
import 'package:savespoon/features/orders/domain/order.dart';

import 'helpers.dart';

class FakePush implements PushPlatform {
  final receivedController = StreamController<PushMessage>.broadcast();
  final openedController = StreamController<PushMessage>.broadcast();
  final shown = <PushMessage>[];
  List<PickupReminder>? scheduled;
  int cleared = 0;
  bool permitted = true;
  bool grant = true;
  bool asked = false;
  int requests = 0;
  String? deviceToken = 'phone-token';
  PushMessage? launch;

  @override
  Future<bool> start() async => deviceToken != null;

  @override
  Future<String?> token() async => deviceToken;

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<PushMessage> get received => receivedController.stream;

  @override
  Stream<PushMessage> get opened => openedController.stream;

  @override
  Future<PushMessage?> launchMessage() async {
    final message = launch;
    launch = null;
    return message;
  }

  @override
  Future<void> show(PushMessage message) async => shown.add(message);

  @override
  Future<bool> isPermitted() async => permitted;

  @override
  Future<bool> requestPermission() async {
    requests++;
    permitted = grant;
    return grant;
  }

  int settingsOpened = 0;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<bool> wasAsked() async => asked;

  @override
  Future<void> markAsked() async => asked = true;

  @override
  Future<void> replaceReminders(List<PickupReminder> reminders) async =>
      scheduled = reminders;

  @override
  Future<void> clearReminders() async => cleared++;
}

class _Server {
  final requests = <http.Request>[];
  Map<String, dynamic> prefs = {
    'itemChanges': true,
    'pickupReminders': true,
    'favourites': true,
  };
  List<Map<String, dynamic>> orders = [];
  bool failPrefs = false;
  List<Map<String, dynamic>> inbox = [];
  int unread = 0;

  Iterable<http.Request> called(String method, String path) => requests.where(
    (request) => request.method == method && request.url.path == path,
  );

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/api/notifications/unread-count') {
      return jsonResponse({'unreadCount': unread});
    }
    if (path == '/api/notifications/preferences') {
      if (failPrefs) return jsonResponse({'error': 'Server is down'}, 500);
      if (request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        prefs = {...prefs, ...body['prefs'] as Map<String, dynamic>};
      }
      return jsonResponse({'prefs': prefs});
    }
    if (path == '/api/notifications') {
      return jsonResponse({'notifications': inbox, 'unreadCount': unread});
    }
    if (path == '/api/orders') {
      return jsonResponse({'orders': orders, 'hasMore': false});
    }
    return jsonResponse({'ok': true});
  }
}

Map<String, dynamic> _order({
  String id = 'o1',
  String status = 'pending',
  required DateTime start,
  DateTime? created,
}) => {
  '_id': id,
  'itemName': 'Nasi Lemak',
  'stallName': 'Warung Pak Din',
  'quantity': 2,
  'totalPrice': 9,
  'pickupStart': start.toUtc().toIso8601String(),
  'pickupEnd': start.add(const Duration(hours: 1)).toUtc().toIso8601String(),
  'status': status,
  'createdAt': ?created?.toUtc().toIso8601String(),
};

Order _parsed(Map<String, dynamic> json) => Order.fromJson(json);

({NotificationsController controller, FakePush push, _Server server})
_controller({DateTime? now}) {
  final server = _Server();
  final api = ApiClient(client: MockClient(server.handle));
  final push = FakePush();
  final controller = NotificationsController(
    platform: push,
    repository: NotificationRepository(api),
    orders: OrderRepository(api),
    clock: () => now ?? DateTime.now(),
  );
  return (controller: controller, push: push, server: server);
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final now = DateTime(2026, 11, 20, 12);

  group('pickup reminders', () {
    test('an open order gets one 30 minutes before pickup', () {
      final start = now.add(const Duration(hours: 2));
      final reminders = planReminders([
        _parsed(_order(start: start, created: now)),
      ], now);

      expect(reminders, hasLength(2));
      final [opens, ends] = reminders;
      expect(opens.at, start.subtract(reminderLead));
      expect(opens.title, 'Pickup opens in 30 minutes');
      expect(opens.body, startsWith('2 x Nasi Lemak at Warung Pak Din. '));
      expect(opens.id, reminderIdFor('o1'));
      expect(
        ends.at,
        start.add(const Duration(hours: 1)).subtract(reminderLead),
      );
      expect(ends.title, 'Pickup ends in 30 minutes');
      expect(
        ends.body,
        startsWith(
          "Don't forget to collect 2 x Nasi Lemak at Warung Pak Din before ",
        ),
      );
      expect(ends.id, isNot(opens.id));
    });

    test('an order placed after the opening reminder gets only the closing '
        'one', () {
      final later = now.add(const Duration(hours: 2));
      final reminders = planReminders([
        _parsed(
          _order(
            start: later,
            created: later.subtract(const Duration(minutes: 15)),
          ),
        ),
      ], now);
      expect(reminders.map((item) => item.title), [
        'Pickup ends in 30 minutes',
      ]);
    });

    test('none for cancelled orders or when both times have passed', () {
      final soon = now.subtract(const Duration(minutes: 50));
      expect(
        planReminders([
          _parsed(
            _order(
              id: 'o2',
              start: now.add(const Duration(hours: 2)),
              status: 'cancelled',
            ),
          ),
          _parsed(_order(id: 'o3', start: soon, created: soon)),
        ], now),
        isEmpty,
      );
    });

    test('the pickup window reads like 5:00–6:00 PM', () {
      expect(
        pickupWindowLabel(
          DateTime(2026, 11, 20, 17),
          DateTime(2026, 11, 20, 18),
        ),
        '5:00–6:00 PM',
      );
      expect(
        pickupWindowLabel(
          DateTime(2026, 11, 20, 11, 30),
          DateTime(2026, 11, 20, 12, 30),
        ),
        '11:30 AM–12:30 PM',
      );
    });

    test('reminder IDs are stable and positive', () {
      expect(reminderIdFor('abc'), reminderIdFor('abc'));
      expect(reminderIdFor('abc'), isNot(reminderIdFor('abd')));
      expect(reminderIdFor('65f0a1b2c3d4e5f6a7b8c9d0'), greaterThan(0));
    });
  });

  group('where a tap leads', () {
    test('a stock alert opens that listing for its vendor only', () {
      const link = NotificationLink(
        type: NotificationType.stockLow,
        listingId: 'l1',
      );
      expect(notificationLocation(link, 'vendor'), '/vendor/listings/l1');
      expect(notificationLocation(link, 'customer'), isNull);
    });

    test('vendor order alerts lead nowhere until vendors can view orders', () {
      for (final type in [
        NotificationType.newOrder,
        NotificationType.orderCancelled,
      ]) {
        expect(
          notificationLocation(
            NotificationLink(type: type, listingId: 'l1'),
            'vendor',
          ),
          isNull,
        );
      }
    });

    test('customers open the order or the food', () {
      expect(
        notificationLocation(
          const NotificationLink(
            type: NotificationType.pickupReminder,
            orderId: 'o1',
          ),
          'customer',
        ),
        '/customer/orders/o1',
      );
      expect(
        notificationLocation(
          const NotificationLink(
            type: NotificationType.favouriteBack,
            listingId: 'l1',
          ),
          'customer',
        ),
        '/customer/food/l1',
      );
    });

    test('a notification for the other role leads nowhere', () {
      expect(
        notificationLocation(
          const NotificationLink(
            type: NotificationType.newOrder,
            listingId: 'l1',
          ),
          'customer',
        ),
        isNull,
      );
    });
  });

  group('controller', () {
    testWidgets('signing in registers the phone and schedules reminders', (
      tester,
    ) async {
      final setup = _controller(now: now);
      setup.server.unread = 3;
      setup.server.orders = [
        _order(start: now.add(const Duration(hours: 2)), created: now),
      ];

      await tester.runAsync(() async {
        await setup.controller.signedIn('customer');
        await _settle();
      });

      final register = setup.server.called('PUT', '/api/notifications/devices');
      expect(jsonDecode(register.single.body), {'token': 'phone-token'});
      expect(setup.controller.unreadCount, 3);
      expect(setup.push.scheduled, hasLength(2));
      setup.controller.dispose();
    });

    testWidgets('vendors get no reminders', (tester) async {
      final setup = _controller(now: now);
      await tester.runAsync(() async {
        await setup.controller.signedIn('vendor');
        await _settle();
      });
      expect(setup.push.scheduled, isNull);
      expect(setup.server.called('GET', '/api/orders'), isEmpty);
      setup.controller.dispose();
    });

    testWidgets('switching reminders off clears them instead', (tester) async {
      final setup = _controller(now: now);
      setup.server.prefs = {...setup.server.prefs, 'pickupReminders': false};
      await tester.runAsync(() async {
        await setup.controller.signedIn('customer');
        await _settle();
      });
      expect(setup.push.scheduled, isNull);
      expect(setup.push.cleared, greaterThan(0));
      setup.controller.dispose();
    });

    testWidgets('logging out removes the phone and its reminders', (
      tester,
    ) async {
      final setup = _controller(now: now);
      await tester.runAsync(() async {
        await setup.controller.signedIn('customer');
        await _settle();
        await setup.controller.beforeSignOut();
      });
      final removed = setup.server.called(
        'DELETE',
        '/api/notifications/devices',
      );
      expect(jsonDecode(removed.single.body), {'token': 'phone-token'});
      expect(setup.push.cleared, greaterThan(0));
      expect(setup.controller.role, isNull);
      expect(setup.controller.unreadCount, 0);
      setup.controller.dispose();
    });

    testWidgets('without Firebase nothing is registered but reminders work', (
      tester,
    ) async {
      final setup = _controller(now: now);
      setup.push.deviceToken = null;
      setup.server.orders = [
        _order(start: now.add(const Duration(hours: 2)), created: now),
      ];
      await tester.runAsync(() async {
        await setup.controller.signedIn('customer');
        await _settle();
      });
      expect(setup.server.called('PUT', '/api/notifications/devices'), isEmpty);
      expect(setup.push.scheduled, hasLength(2));
      setup.controller.dispose();
    });

    testWidgets('a re-sync push reschedules; others are shown and counted', (
      tester,
    ) async {
      final setup = _controller(now: now);
      await tester.runAsync(() async {
        await setup.controller.signedIn('customer');
        await _settle();
        setup.push.scheduled = null;
        setup.server.orders = [
          _order(start: now.add(const Duration(hours: 3)), created: now),
        ];
        setup.push.receivedController.add(
          const PushMessage(data: {'type': 'orders_changed'}),
        );
        await _settle();
        expect(setup.push.scheduled, hasLength(2));
        expect(setup.push.shown, isEmpty);

        setup.server.unread = 1;
        setup.push.receivedController.add(
          const PushMessage(
            data: {'type': 'item_changed', 'orderId': 'o1'},
            title: 'Item Details Changed',
          ),
        );
        await _settle();
      });
      expect(setup.push.shown.single.title, 'Item Details Changed');
      expect(setup.controller.unreadCount, 1);
      setup.controller.dispose();
    });

    testWidgets('a tapped push waits to be opened and is marked read', (
      tester,
    ) async {
      final setup = _controller(now: now);
      await tester.runAsync(() async {
        await setup.controller.signedIn('customer');
        setup.push.openedController.add(
          const PushMessage(
            data: {
              'type': 'favourite_back',
              'listingId': 'l9',
              'notificationId': 'n1',
            },
          ),
        );
        await _settle();
      });
      expect(setup.controller.pendingLink?.listingId, 'l9');
      expect(
        setup.server.called('POST', '/api/notifications/n1/read'),
        hasLength(1),
      );
      expect(setup.controller.takePendingLink()?.listingId, 'l9');
      expect(setup.controller.pendingLink, isNull);
      setup.controller.dispose();
    });

    testWidgets('the launch tap is kept for the tab shell', (tester) async {
      final setup = _controller(now: now);
      setup.push.launch = const PushMessage(
        data: {'type': 'new_order', 'listingId': 'l2'},
      );
      await tester.runAsync(() async {
        await setup.controller.signedIn('vendor');
        await _settle();
      });
      expect(setup.controller.pendingLink?.type, NotificationType.newOrder);
      setup.controller.dispose();
    });

    testWidgets('permission is asked once per phone', (tester) async {
      final setup = _controller(now: now);
      await tester.runAsync(() async {
        await setup.controller.askOnce();
        await setup.controller.askOnce();
      });
      expect(setup.push.requests, 1);
      setup.controller.dispose();
    });
  });

  group('screens', () {
    Widget host({
      required _Server server,
      required NotificationsController? controller,
      required Widget child,
      List<RouteBase> extraRoutes = const [],
    }) {
      final api = ApiClient(client: MockClient(server.handle));
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => child),
          ...extraRoutes,
        ],
      );
      return MultiProvider(
        providers: [
          Provider<NotificationRepository>.value(
            value: NotificationRepository(api),
          ),
          if (controller != null)
            ChangeNotifierProvider<NotificationsController>.value(
              value: controller,
            ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      );
    }

    Map<String, dynamic> note({
      String id = 'n1',
      String type = 'favourite_back',
      bool read = false,
    }) => {
      '_id': id,
      'type': type,
      'title': 'Back in Stock',
      'body': 'Kuih Box from Kak Ros is available again.',
      'listingId': 'l1',
      'createdAt': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .toUtc()
          .toIso8601String(),
      'readAt': read ? DateTime.now().toUtc().toIso8601String() : null,
    };

    testWidgets('the inbox lists notifications and a tap opens and reads one', (
      tester,
    ) async {
      final server = _Server()
        ..inbox = [note(), note(id: 'n2', read: true)]
        ..unread = 1;
      await tester.pumpWidget(
        host(
          server: server,
          controller: null,
          child: const NotificationsPage(role: 'customer'),
          extraRoutes: [
            GoRoute(
              path: '/customer/food/:id',
              builder: (context, state) =>
                  Text('food ${state.pathParameters['id']}'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Back in Stock'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);
      expect(find.text('5 min ago'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();

      expect(server.called('POST', '/api/notifications/n1/read'), hasLength(1));
      expect(find.text('food l1'), findsOneWidget);
    });

    testWidgets('the menu always offers Settings, even with an empty inbox', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          server: _Server(),
          controller: null,
          child: const NotificationsPage(role: 'vendor'),
          extraRoutes: [
            GoRoute(
              path: '/vendor/profile/notifications',
              builder: (context, state) =>
                  const Scaffold(body: Text('Settings page')),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('inbox-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mark-all-read')), findsNothing);
      expect(find.byKey(const ValueKey('clear-all')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('inbox-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Settings page'), findsOneWidget);
    });

    testWidgets('an empty inbox says so', (tester) async {
      await tester.pumpWidget(
        host(
          server: _Server(),
          controller: null,
          child: const NotificationsPage(role: 'vendor'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No notifications yet'), findsOneWidget);
    });

    testWidgets('the bell shows the unread count, and hides without setup', (
      tester,
    ) async {
      final setup = _controller(now: now);
      setup.controller.setUnreadCount(4);
      await tester.pumpWidget(
        host(
          server: setup.server,
          controller: setup.controller,
          child: const Scaffold(body: NotificationBell(role: 'customer')),
        ),
      );
      expect(find.text('4'), findsOneWidget);
      expect(find.byTooltip('Notifications, 4 unread'), findsOneWidget);

      await tester.pumpWidget(
        host(
          server: setup.server,
          controller: null,
          child: const Scaffold(body: NotificationBell(role: 'customer')),
        ),
      );
      expect(find.byKey(const ValueKey('notification-bell')), findsNothing);
      setup.controller.dispose();
    });

    testWidgets('the bell counts and wiggles for a type that sends no push', (
      tester,
    ) async {
      final setup = _controller();
      await setup.controller.signedIn('vendor');
      await tester.pumpWidget(
        ChangeNotifierProvider<NotificationsController?>.value(
          value: setup.controller,
          child: const MaterialApp(
            home: Scaffold(body: NotificationBell(role: 'vendor')),
          ),
        ),
      );
      double turns() => tester
          .widget<RotationTransition>(find.byKey(const ValueKey('bell-wiggle')))
          .turns
          .value;
      await tester.pump(const Duration(seconds: 1));
      expect(turns(), 0);

      setup.server.unread = 1;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.text('1'), findsOneWidget);
      expect(turns(), isNot(0));
      await tester.pumpAndSettle();
      expect(turns(), 0);

      setup.server.unread = 0;
      await setup.controller.refreshUnread();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(turns(), 0);

      await tester.pumpWidget(const SizedBox.shrink());
      setup.controller.dispose();
    });

    testWidgets('the bell keeps still when animations are off', (tester) async {
      final setup = _controller();
      await setup.controller.signedIn('vendor');
      await tester.pumpWidget(
        ChangeNotifierProvider<NotificationsController?>.value(
          value: setup.controller,
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: NotificationBell(role: 'vendor')),
            ),
          ),
        ),
      );
      setup.controller.setUnreadCount(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.text('2'), findsOneWidget);
      expect(
        tester
            .widget<RotationTransition>(
              find.byKey(const ValueKey('bell-wiggle')),
            )
            .turns
            .value,
        0,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      setup.controller.dispose();
    });

    testWidgets('Mark All as Read clears every dot and tells the server', (
      tester,
    ) async {
      final server = _Server()
        ..inbox = [note(), note(id: 'n2')]
        ..unread = 2;
      await tester.pumpWidget(
        host(
          server: server,
          controller: null,
          child: const NotificationsPage(role: 'vendor'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unread-dot')), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('inbox-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mark-all-read')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
      final call = server.called('POST', '/api/notifications/read-all');
      expect(jsonDecode(call.single.body), <String, dynamic>{});

      await tester.tap(find.byKey(const ValueKey('inbox-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mark-all-read')), findsNothing);
      expect(find.byKey(const ValueKey('clear-all')), findsOneWidget);
    });

    testWidgets('Clear All asks first, then empties the inbox', (tester) async {
      final server = _Server()
        ..inbox = [note(), note(id: 'n2', read: true)]
        ..unread = 1;
      await tester.pumpWidget(
        host(
          server: server,
          controller: null,
          child: const NotificationsPage(role: 'customer'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('inbox-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-all')));
      await tester.pumpAndSettle();
      expect(find.text('Clear all notifications?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.called('DELETE', '/api/notifications'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('inbox-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('clear-all-confirm')));
      await tester.pumpAndSettle();

      expect(server.called('DELETE', '/api/notifications'), hasLength(1));
      expect(find.text('No notifications yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('inbox-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('clear-all')), findsNothing);
      expect(find.byKey(const ValueKey('inbox-settings')), findsOneWidget);
    });

    testWidgets('swiping one left clears only that one', (tester) async {
      final server = _Server()
        ..inbox = [note(), note(id: 'n2')]
        ..unread = 2;
      await tester.pumpWidget(
        host(
          server: server,
          controller: null,
          child: const NotificationsPage(role: 'customer'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.fling(
        find.byKey(const ValueKey('notification-n1')),
        const Offset(-500, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notification-n1')), findsNothing);

      expect(server.called('DELETE', '/api/notifications/n1'), hasLength(1));
      expect(find.byKey(const ValueKey('notification-n1')), findsNothing);
      expect(find.byKey(const ValueKey('notification-n2')), findsOneWidget);
    });

    testWidgets('marking one read sends a JSON body the server accepts', (
      tester,
    ) async {
      final server = _Server()
        ..inbox = [note(type: 'new_order')]
        ..unread = 1;
      await tester.pumpWidget(
        host(
          server: server,
          controller: null,
          child: const NotificationsPage(role: 'vendor'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('notification-n1')));
      await tester.pumpAndSettle();

      final call = server.called('POST', '/api/notifications/n1/read');
      expect(jsonDecode(call.single.body), <String, dynamic>{});
      expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
      expect(find.byType(NotificationsPage), findsOneWidget);
    });

    testWidgets('My Profile shows each setting as On or Off with a pencil', (
      tester,
    ) async {
      final server = _Server()
        ..prefs = {
          'itemChanges': true,
          'pickupReminders': false,
          'favourites': true,
        };
      final opened = <String>[];
      await tester.pumpWidget(
        host(
          server: server,
          controller: null,
          child: Scaffold(
            body: NotificationSettingsSection(
              role: 'customer',
              onEdit: (location) async => opened.add(location),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pickup reminders'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('notification-value-pickupReminders')),
            )
            .data,
        'Off',
      );
      expect(find.byType(Switch), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('notification-settings-edit')),
      );
      await tester.pumpAndSettle();
      expect(opened, ['/customer/profile/notifications']);
      expect(
        server.called('GET', '/api/notifications/preferences'),
        hasLength(2),
      );
    });

    testWidgets('a failed load shows a note without its own Try Again, and '
        "reloads with My Profile", (tester) async {
      final server = _Server()..failPrefs = true;
      Widget section(int reloads) => host(
        server: server,
        controller: null,
        child: Scaffold(
          body: NotificationSettingsSection(
            role: 'customer',
            onEdit: (_) async {},
            reloads: reloads,
          ),
        ),
      );
      await tester.pumpWidget(section(0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('notification-settings-failed')),
        findsOneWidget,
      );
      expect(find.text('Try Again'), findsNothing);

      server.failPrefs = false;
      await tester.pumpWidget(section(1));
      await tester.pumpAndSettle();
      expect(find.text('Pickup reminders'), findsOneWidget);
    });

    testWidgets('vendors only see Order alerts', (tester) async {
      final server = _Server()..prefs = {'orderAlerts': true};
      await tester.pumpWidget(
        host(
          server: server,
          controller: null,
          child: Scaffold(
            body: NotificationSettingsSection(
              role: 'vendor',
              onEdit: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Order alerts'), findsOneWidget);
      expect(find.text('Stock alerts'), findsOneWidget);
      expect(find.text('Pickup reminders'), findsNothing);
    });

    testWidgets('Save Changes stays off until a switch changes, then saves '
        'and closes with a message', (tester) async {
      final server = _Server();
      String? closedWith;
      await tester.pumpWidget(
        host(
          server: server,
          controller: null,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  closedWith = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) =>
                          const NotificationSettingsPage(role: 'customer'),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      FilledButton save() => tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('notification-settings-save')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(find.text('Notification Settings'), findsOneWidget);
      expect(save().onPressed, isNull);

      final favourites = find.byKey(
        const ValueKey('notification-switch-favourites'),
      );
      await tester.tap(favourites);
      await tester.pump();
      expect(save().onPressed, isNotNull);
      await tester.tap(favourites);
      await tester.pump();
      expect(save().onPressed, isNull);

      await tester.tap(favourites);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('notification-settings-save')),
      );
      await tester.pumpAndSettle();

      final put = server.called('PUT', '/api/notifications/preferences');
      expect(
        (jsonDecode(put.single.body) as Map)['prefs']['favourites'],
        isFalse,
      );
      expect(closedWith, 'Notification settings saved.');
      expect(find.byType(NotificationSettingsPage), findsNothing);
    });

    testWidgets('notifications off on the phone show only the note, then '
        'Open Settings after a refusal', (tester) async {
      final setup = _controller(now: now);
      setup.push
        ..permitted = false
        ..grant = false;
      await tester.runAsync(() => setup.controller.signedIn('customer'));
      await tester.pumpWidget(
        host(
          server: setup.server,
          controller: setup.controller,
          child: Scaffold(
            body: NotificationSettingsSection(
              role: 'customer',
              onEdit: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notifications-off')), findsOneWidget);
      expect(find.text('Pickup reminders'), findsNothing);
      expect(
        find.byKey(const ValueKey('notification-settings-edit')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('notifications-turn-on')));
      await tester.pumpAndSettle();

      expect(setup.push.requests, 1);
      expect(find.textContaining('Open Settings and turn on'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('notifications-turn-on')));
      await tester.pumpAndSettle();
      expect(setup.push.settingsOpened, 1);
      expect(setup.push.requests, 1);

      setup.push.grant = true;
      await tester.runAsync(() => setup.controller.turnOn());
      await tester.pump(const Duration(milliseconds: 150));
      // Mid-way, the note fades out while the settings fade in.
      expect(find.byKey(const ValueKey('notifications-off')), findsOneWidget);
      expect(find.text('Pickup reminders'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notifications-off')), findsNothing);
      expect(find.text('Pickup reminders'), findsOneWidget);
      setup.controller.dispose();
    });

    testWidgets('Notification Settings shows no switches while notifications '
        'are off', (tester) async {
      final setup = _controller(now: now);
      setup.push.permitted = false;
      await tester.runAsync(() => setup.controller.signedIn('vendor'));
      setup.server.prefs = {'orderAlerts': true, 'stockAlerts': true};
      await tester.pumpWidget(
        host(
          server: setup.server,
          controller: setup.controller,
          child: const NotificationSettingsPage(role: 'vendor'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('notifications-off')), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Save Changes'), findsNothing);

      setup.push.grant = true;
      await tester.runAsync(() => setup.controller.turnOn());
      await tester.pumpAndSettle();
      expect(find.text('Stock alerts'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));

      await tester.tap(
        find.byKey(const ValueKey('phone-notification-settings')),
      );
      await tester.pump();
      expect(setup.push.settingsOpened, 1);
      setup.controller.dispose();
    });
  });
}
