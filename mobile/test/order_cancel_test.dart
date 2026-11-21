import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/routing/app_router.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/orders/data/order_repository.dart';
import 'package:savespoon/features/orders/domain/order.dart';
import 'package:savespoon/features/orders/presentation/pages/order_cancelled_page.dart';
import 'package:savespoon/features/orders/presentation/pages/order_confirmation_page.dart';
import 'package:savespoon/features/orders/presentation/pages/order_details_page.dart';
import 'package:savespoon/features/orders/presentation/widgets/order_card.dart';

import 'helpers.dart';
import 'order_repository_test.dart' show orderJson;

Map<String, dynamic> _order({
  String id = 'o1',
  String item = 'Nasi Lemak',
  String status = 'pending',
  Duration? cancelFor = const Duration(hours: 1),
  bool ended = false,
  List<Map<String, dynamic>> checkoutOrders = const [],
}) => {
  ...orderJson(
    id: id,
    status: status,
    pickupEnd: DateTime.now().add(Duration(hours: ended ? -1 : 2)),
  ),
  'itemName': item,
  'checkoutId': 'c1',
  'checkoutOrders': checkoutOrders,
  'otherCancellable': checkoutOrders
      .where((other) => other['canCancel'] == true)
      .length,
  'cancelUntil': cancelFor == null
      ? null
      : DateTime.now().add(cancelFor).toUtc().toIso8601String(),
  'cancelledAt': status == 'cancelled'
      ? DateTime.now().toUtc().toIso8601String()
      : null,
};

Map<String, dynamic> _checkoutItem(String item, {bool canCancel = true}) => {
  '_id': 'x-$item',
  'itemName': item,
  'quantity': 1,
  'stallName': 'Kedai B',
  'canCancel': canCancel,
};

class _Server {
  _Server(this.details, {this.cancel});

  Map<String, dynamic> details;
  final http.Response Function(Map<String, dynamic> body)? cancel;
  final List<Map<String, dynamic>> cancelBodies = [];
  final List<String> cancelPaths = [];

  http.Response respond(http.Request request) {
    if (request.url.path.endsWith('/cancel')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      cancelBodies.add(body);
      cancelPaths.add(request.url.path);
      final response = cancel!(body);
      if (response.statusCode == 200) {
        details = _order(status: 'cancelled', cancelFor: null);
      }
      return response;
    }
    if (request.url.path == '/api/orders/o1') {
      return jsonResponse({'order': details});
    }
    return jsonResponse({'orders': <Object>[], 'hasMore': false});
  }

  OrderRepository repository() => OrderRepository(
    ApiClient(client: MockClient((request) async => respond(request))),
  );
}

Future<void> _pump(WidgetTester tester, _Server server, GoRouter router) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    Provider<OrderRepository>(
      create: (_) => server.repository(),
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

GoRoute _ordersRoute() => GoRoute(
  path: AppRoutes.customerOrders,
  builder: (context, state) => const Scaffold(body: Text('My Orders list')),
);

Future<_Server> _openDetails(WidgetTester tester, _Server server) async {
  await _pump(
    tester,
    server,
    GoRouter(
      initialLocation: AppRoutes.orderDetailsFor('o1'),
      routes: [
        _ordersRoute(),
        GoRoute(
          path: AppRoutes.orderDetails,
          builder: (context, state) =>
              OrderDetailsPage(orderId: state.pathParameters['id']!),
        ),
      ],
    ),
  );
  return server;
}

Future<_Server> _openPlaced(
  WidgetTester tester,
  _Server server,
  List<Order> orders,
) async {
  await _pump(
    tester,
    server,
    GoRouter(
      initialLocation: '/placed',
      routes: [
        _ordersRoute(),
        GoRoute(
          path: '/placed',
          builder: (context, state) =>
              OrderConfirmationPage(orders: orders, onDone: (_) {}),
        ),
      ],
    ),
  );
  return server;
}

final _button = find.byKey(const ValueKey('cancel-order-button'));
final _note = find.byKey(const ValueKey('cancel-note'));

http.Response _cancelled(Map<String, dynamic> body) => jsonResponse({
  'cancelled': [_order(status: 'cancelled', cancelFor: null)],
  'skipped': <Object>[],
});

Future<void> _chooseReason(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('cancel-reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('Order Details', () {
    testWidgets('an open order says until when, and cancels with a reason', (
      tester,
    ) async {
      final server = await _openDetails(
        tester,
        _Server(_order(), cancel: _cancelled),
      );

      expect(
        find.descendant(
          of: _note,
          matching: find.textContaining('You can cancel this order until '),
        ),
        findsOneWidget,
      );
      await tester.tap(_button);
      await tester.pumpAndSettle();

      expect(find.text('Cancel this order?'), findsOneWidget);
      expect(find.textContaining('go back on sale'), findsNothing);
      expect(find.text('Choose a reason (optional)'), findsOneWidget);
      expect(find.textContaining('ordered together'), findsNothing);
      expect(find.text('Cancel This Order Only'), findsNothing);
      await _chooseReason(tester, "Can't Make the Pickup Time");
      await tester.tap(find.text('Cancel Order').last);
      await tester.pumpAndSettle();

      expect(server.cancelBodies.single, {
        'reason': 'cannot_make_pickup',
        'wholeCheckout': false,
      });
      expect(find.byType(OrderCancelledPage), findsOneWidget);
      expect(find.text('Order Cancelled'), findsOneWidget);

      await tester.tap(find.text('Back to My Orders'));
      await tester.pumpAndSettle();
      expect(find.text('My Orders list'), findsOneWidget);
    });

    testWidgets('Keep Order closes the dialog without cancelling', (
      tester,
    ) async {
      final server = await _openDetails(
        tester,
        _Server(_order(), cancel: _cancelled),
      );

      await tester.tap(_button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep Order'));
      await tester.pumpAndSettle();

      expect(server.cancelBodies, isEmpty);
      expect(find.byType(OrderCancelledPage), findsNothing);
    });

    testWidgets('the rest of the checkout is listed and can be cancelled', (
      tester,
    ) async {
      final server = await _openDetails(
        tester,
        _Server(
          _order(
            checkoutOrders: [
              _checkoutItem('Kuih'),
              _checkoutItem('Teh Tarik', canCancel: false),
            ],
          ),
          cancel: _cancelled,
        ),
      );

      await tester.tap(_button);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This item was ordered together with 2 other items in the same '
          'checkout:',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('1 x Kuih'), findsOneWidget);
      expect(find.textContaining('can no longer be cancelled'), findsOneWidget);
      expect(find.text('Cancel This Order Only'), findsOneWidget);
      await tester.tap(find.text('Cancel All 2 Orders'));
      await tester.pumpAndSettle();

      expect(server.cancelBodies.single, {'wholeCheckout': true});
    });

    testWidgets(
      'during pickup, only a note says it can no longer be cancelled',
      (tester) async {
        await _openDetails(tester, _Server(_order(cancelFor: null)));

        expect(_button, findsNothing);
        expect(
          find.descendant(
            of: _note,
            matching: find.text(
              'Pickup has started, so this order can no longer be cancelled.',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    for (final (label, order) in [
      ('ended', _order(cancelFor: null, ended: true)),
      ('completed', _order(status: 'completed', cancelFor: null)),
    ]) {
      testWidgets('a $label order shows no button and no note', (tester) async {
        await _openDetails(tester, _Server(order));

        expect(_button, findsNothing);
        expect(_note, findsNothing);
      });
    }

    testWidgets('a cancelled order shows when, and no button', (tester) async {
      await _openDetails(
        tester,
        _Server(_order(status: 'cancelled', cancelFor: null)),
      );

      expect(_button, findsNothing);
      expect(_note, findsNothing);
      expect(find.byKey(const ValueKey('order-cancelled-on')), findsOneWidget);
      expect(find.text('Cancelled On'), findsOneWidget);
    });

    testWidgets('a refused cancel shows the server message', (tester) async {
      final server = await _openDetails(
        tester,
        _Server(
          _order(),
          cancel: (_) => jsonResponse({
            'code': 'CANCEL_LIMIT',
            'error':
                'You can cancel up to 5 times in 24 hours. '
                'Try again in about 3 hours.',
          }, 429),
        ),
      );

      await tester.tap(_button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel Order').last);
      await tester.pumpAndSettle();

      expect(server.cancelBodies, hasLength(1));
      expect(
        find.textContaining('Try again in about 3 hours.'),
        findsOneWidget,
      );
      expect(find.byType(OrderCancelledPage), findsNothing);
      expect(_button, findsOneWidget);
    });
  });

  group('Order Details layout', () {
    testWidgets('the cancel note sits above an outlined Cancel Order', (
      tester,
    ) async {
      await _openDetails(tester, _Server(_order()));

      expect(
        find.descendant(of: _button, matching: find.text('Cancel Order')),
        findsOneWidget,
      );
      expect(tester.widget(_button), isA<OutlinedButton>());
      expect(
        tester.getTopLeft(_note).dy,
        lessThan(tester.getTopLeft(_button).dy),
      );
    });
  });

  group('time labels', () {
    final now = DateTime(2026, 11, 15, 12);

    Future<List<String>> labels(
      WidgetTester tester,
      List<DateTime> times,
    ) async {
      final out = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              out
                ..clear()
                ..addAll([
                  for (final time in times)
                    orderPlacedLabel(context, time, now: now),
                ]);
              return const SizedBox();
            },
          ),
        ),
      );
      return out;
    }

    testWidgets('name today, yesterday and tomorrow, else show the date', (
      tester,
    ) async {
      final result = await labels(tester, [
        DateTime(2026, 11, 15, 15, 45),
        DateTime(2026, 11, 14, 9, 5),
        DateTime(2026, 11, 16, 17, 30),
        DateTime(2026, 11, 10, 15, 45),
      ]);

      expect(result, [
        'Today, 3:45 PM',
        'Yesterday, 9:05 AM',
        'Tomorrow, 5:30 PM',
        'Nov 10, 3:45 PM',
      ]);
    });

    testWidgets('an order card shows the date only when asked', (tester) async {
      final order = Order.fromJson({
        ...orderJson(),
        'createdAt': DateTime(2026, 11, 10, 15, 45).toUtc().toIso8601String(),
      });
      Future<void> card({required bool showDate}) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: OrderCard(
              order: order,
              now: now,
              onInfo: () {},
              showPlacedDate: showDate,
            ),
          ),
        ),
      );

      await card(showDate: true);
      expect(find.text('Nov 10, 3:45 PM'), findsOneWidget);

      await card(showDate: false);
      expect(find.text('3:45 PM'), findsOneWidget);
    });
  });

  group('Order Placed', () {
    Order placed(String id, String item, {Duration? cancelFor}) =>
        Order.fromJson({
          ...orderJson(id: id),
          'itemName': item,
          'cancelUntil': DateTime.now()
              .add(cancelFor ?? const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        });

    testWidgets('shows Title Case, the payment method and Cancel Order', (
      tester,
    ) async {
      final server = await _openPlaced(
        tester,
        _Server(_order(), cancel: _cancelled),
        [placed('o1', 'Nasi Lemak')],
      );

      expect(find.text('Order Placed!'), findsOneWidget);
      expect(
        tester.widget(find.byKey(const ValueKey('order-placed-cancel'))),
        isA<OutlinedButton>(),
      );
      final payment = find.byKey(const ValueKey('order-placed-payment'));
      expect(
        find.descendant(of: payment, matching: find.text('Payment Method')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: payment, matching: find.text('Pay at Pickup')),
        findsOneWidget,
      );

      expect(find.text('Total'), findsOneWidget, reason: 'single orders too');
      final note = find.byKey(const ValueKey('order-placed-cancel-note'));
      expect(
        find.descendant(
          of: note,
          matching: find.textContaining('You can cancel this order until '),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(note).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('order-placed-cancel')))
              .dy,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('order-placed-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this order?'), findsOneWidget);
      await tester.tap(find.text('Cancel Order').last);
      await tester.pumpAndSettle();

      expect(server.cancelPaths.single, '/api/orders/o1/cancel');
      expect(server.cancelBodies.single, {'wholeCheckout': false});
      expect(find.text('Order Cancelled'), findsOneWidget);
    });

    testWidgets('Pay at Pickup ends at the row end on a wide screen', (
      tester,
    ) async {
      await _openPlaced(tester, _Server(_order()), [
        placed('o1', 'Nasi Lemak'),
      ]);

      final payment = find.byKey(const ValueKey('order-placed-payment'));
      final label = find.descendant(
        of: payment,
        matching: find.text('Pay at Pickup'),
      );
      expect(
        tester.getTopRight(label).dx,
        moreOrLessEquals(tester.getTopRight(payment).dx, epsilon: 1),
      );
    });

    testWidgets('several orders are cancelled together', (tester) async {
      final server = await _openPlaced(
        tester,
        _Server(_order(), cancel: _cancelled),
        [placed('o1', 'Nasi Lemak'), placed('o2', 'Kuih')],
      );

      expect(find.text('Orders Placed!'), findsOneWidget);
      expect(
        find.textContaining('You can cancel these orders until '),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel Orders'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel these orders?'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('2 x Kuih', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.text('Keep Orders'), findsOneWidget);
      await tester.tap(find.text('Cancel All 2 Orders'));
      await tester.pumpAndSettle();

      expect(server.cancelBodies.single, {'wholeCheckout': true});
      expect(find.byType(OrderCancelledPage), findsOneWidget);
    });

    testWidgets('the note uses the earliest deadline', (tester) async {
      await _openPlaced(tester, _Server(_order()), [
        placed('o1', 'Nasi Lemak', cancelFor: const Duration(hours: 3)),
        placed('o2', 'Kuih', cancelFor: const Duration(minutes: 4)),
      ]);

      final until = DateTime.now().add(const Duration(minutes: 4));
      final context = tester.element(find.byType(OrderConfirmationPage));
      expect(
        find.text(
          'You can cancel these orders until '
          '${cancelUntilLabel(context, until, DateTime.now())}.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'the note sits under Payment Method, Cancel under Back to Home',
      (tester) async {
        await _openPlaced(tester, _Server(_order()), [
          placed('o1', 'Nasi Lemak'),
        ]);

        double top(Finder finder) => tester.getTopLeft(finder).dy;
        final note = find.byKey(const ValueKey('order-placed-cancel-note'));
        expect(
          top(find.byKey(const ValueKey('order-placed-payment'))),
          lessThan(top(note)),
        );
        expect(top(note), lessThan(top(find.text('Back to Home'))));
        expect(
          top(find.text('Back to Home')),
          lessThan(top(find.byKey(const ValueKey('order-placed-cancel')))),
        );
      },
    );

    testWidgets('Order Cancelled slides in like Order Placed', (tester) async {
      await _openPlaced(tester, _Server(_order(), cancel: _cancelled), [
        placed('o1', 'Nasi Lemak'),
      ]);
      await tester.tap(find.byKey(const ValueKey('order-placed-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel Order').last);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final page = find.byType(OrderCancelledPage);
      expect(tester.getTopLeft(page).dx, greaterThan(0), reason: 'mid-slide');
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(page).dx, 0);
    });

    testWidgets('buttons only work once the tick has finished', (tester) async {
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: OrderConfirmationPage(
            orders: [placed('o1', 'Nasi Lemak')],
            onDone: (_) => done++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Back to Home'), warnIfMissed: false);
      expect(done, 0);

      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to Home'));
      expect(done, 1);
    });

    testWidgets('no Cancel Order once cancelling has closed', (tester) async {
      await _openPlaced(tester, _Server(_order()), [
        Order.fromJson({...orderJson(id: 'o1'), 'cancelUntil': null}),
      ]);

      expect(find.byKey(const ValueKey('order-placed-cancel')), findsNothing);
      expect(
        find.byKey(const ValueKey('order-placed-cancel-note')),
        findsNothing,
      );
      expect(find.text('Back to Home'), findsOneWidget);
    });
  });
}
