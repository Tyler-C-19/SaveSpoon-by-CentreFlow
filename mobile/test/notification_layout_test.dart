import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/core/widgets/brand_title.dart';
import 'package:savespoon/features/notifications/data/notification_repository.dart';
import 'package:savespoon/features/notifications/data/push_platform.dart';
import 'package:savespoon/features/notifications/domain/app_notification.dart';
import 'package:savespoon/features/notifications/presentation/pages/notification_settings_page.dart';
import 'package:savespoon/features/notifications/presentation/pages/notifications_page.dart';
import 'package:savespoon/features/notifications/presentation/providers/notifications_controller.dart';
import 'package:savespoon/features/notifications/presentation/widgets/notification_bell.dart';
import 'package:savespoon/features/notifications/presentation/widgets/notification_settings_section.dart';
import 'package:savespoon/features/orders/data/order_repository.dart';

import 'helpers.dart';

// Like Android 14+: small text grows by [top], and the growth fades out by
// 100 sp.
class _AndroidText extends TextScaler {
  const _AndroidText(this.top);

  final double top;

  @override
  double scale(double fontSize) {
    final fade = ((fontSize - 12) / 88).clamp(0.0, 1.0);
    return fontSize * (top + (1 - top) * fade);
  }

  @override
  double get textScaleFactor => top;
}

class _OffPush extends NoPush {
  const _OffPush();

  @override
  Future<bool> isPermitted() async => false;
}

const _widths = [320.0, 360.0, 411.0];
const _sizes = [1.0, 1.3, 2.0];

const _longTitle = 'Item Details Changed For Your Order Today';
const _longBody =
    'Warung Pak Din Nasi Kandar Original changed the name, description, '
    'halal status and allergens of Nasi Lemak Ayam Goreng Berempah Special. '
    'Check it before pickup.';

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  required double width,
  required double scale,
  NotificationsController? controller,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(
    client: MockClient(
      (request) async => jsonResponse({
        'prefs': {
          'orderAlerts': true,
          'itemChanges': true,
          'pickupReminders': false,
          'favourites': true,
        },
      }),
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<NotificationRepository>.value(
          value: NotificationRepository(api),
        ),
        if (controller != null)
          ChangeNotifierProvider<NotificationsController>.value(
            value: controller,
          ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: _AndroidText(scale),
          ),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppNotification _note({required bool read}) => AppNotification(
  id: 'n1',
  type: NotificationType.itemChanged,
  title: _longTitle,
  body: _longBody,
  orderId: 'o1',
  createdAt: DateTime(2026, 11, 18, 17),
  readAt: read ? DateTime(2026, 11, 18, 18) : null,
);

NotificationsController _controllerWith(PushPlatform push) {
  final api = ApiClient(client: MockClient((_) async => jsonResponse({})));
  return NotificationsController(
    platform: push,
    repository: NotificationRepository(api),
    orders: OrderRepository(api),
  );
}

void main() {
  for (final width in _widths) {
    for (final scale in _sizes) {
      final size = 'width $width, text x$scale';

      testWidgets('an inbox row with long text never overflows ($size)', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final read in [false, true])
                    NotificationTile(
                      item: _note(read: read),
                      now: DateTime(2026, 11, 20, 12),
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull, reason: size);
        expect(find.textContaining('Check it before pickup'), findsNWidgets(2));
      });

      for (final role in ['customer', 'vendor']) {
        testWidgets('the $role notification settings never overflow, with '
            'notifications off ($size)', (tester) async {
          final controller = _controllerWith(const _OffPush());
          await tester.runAsync(() => controller.signedIn(role));
          await _pumpAt(
            tester,
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: NotificationSettingsSection(
                  role: role,
                  onEdit: (_) async {},
                ),
              ),
            ),
            width: width,
            scale: scale,
            controller: controller,
          );
          expect(tester.takeException(), isNull, reason: size);
          expect(
            find.byKey(const ValueKey('notifications-off')),
            findsOneWidget,
          );

          await _pumpAt(
            tester,
            NotificationSettingsPage(role: role),
            width: width,
            scale: scale,
            controller: controller,
          );
          expect(tester.takeException(), isNull, reason: 'page, $size');
          expect(find.text('Save Changes'), findsNothing);
          controller.dispose();

          final on = _controllerWith(const NoPush());
          await tester.runAsync(() => on.signedIn(role));
          await _pumpAt(
            tester,
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: NotificationSettingsSection(
                  role: role,
                  onEdit: (_) async {},
                ),
              ),
            ),
            width: width,
            scale: scale,
            controller: on,
          );
          expect(tester.takeException(), isNull, reason: 'rows, $size');
          await _pumpAt(
            tester,
            NotificationSettingsPage(role: role),
            width: width,
            scale: scale,
            controller: on,
          );
          expect(tester.takeException(), isNull, reason: 'switches, $size');
          expect(find.text('Save Changes'), findsOneWidget);
          on.dispose();
        });
      }

      testWidgets('the header with the bell never overflows ($size)', (
        tester,
      ) async {
        final controller = _controllerWith(const NoPush())..setUnreadCount(120);
        await _pumpAt(
          tester,
          Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              centerTitle: false,
              title: const BrandTitle(),
              actions: const [NotificationBell(role: 'customer')],
            ),
            body: const SizedBox.shrink(),
          ),
          width: width,
          scale: scale,
          controller: controller,
        );
        expect(tester.takeException(), isNull, reason: size);
        expect(find.text('99+'), findsOneWidget);
        controller.dispose();
      });
    }
  }

  testWidgets('the bell grows with the text size', (tester) async {
    final controller = _controllerWith(const NoPush());
    double bellSize() => tester
        .widget<IconButton>(find.byKey(const ValueKey('notification-bell')))
        .iconSize!;

    await _pumpAt(
      tester,
      const Scaffold(body: NotificationBell(role: 'vendor')),
      width: 360,
      scale: 1,
      controller: controller,
    );
    final normal = bellSize();
    await _pumpAt(
      tester,
      const Scaffold(body: NotificationBell(role: 'vendor')),
      width: 360,
      scale: 2,
      controller: controller,
    );
    expect(bellSize(), greaterThan(normal));
    controller.dispose();
  });
}
