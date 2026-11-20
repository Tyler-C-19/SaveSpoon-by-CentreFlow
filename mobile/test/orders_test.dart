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
import 'package:savespoon/features/orders/presentation/pages/order_details_page.dart';
import 'package:savespoon/features/orders/presentation/pages/orders_page.dart';

import 'helpers.dart';
import 'order_repository_test.dart' show orderJson;

Map<String, dynamic> _order(
  String id, {
  String status = 'pending',
  int endsInHours = 2,
  String item = 'Nasi Lemak',
  String stallName = 'Warung Pak Din',
  int daysAgo = 0,
}) => {
  ...orderJson(
    id: id,
    status: status,
    pickupEnd: DateTime.now().add(Duration(hours: endsInHours)),
  ),
  'itemName': item,
  'stallName': stallName,
  // Overrides orderJson's fixed createdAt so date-bucket tests stay
  // relative to today instead of one calendar date.
  'createdAt': DateTime.now()
      .subtract(Duration(days: daysAgo))
      .toUtc()
      .toIso8601String(),
};

class _Server {
  _Server(this.respond);

  final http.Response Function(http.Request request) respond;
  final List<http.Request> requests = [];

  OrderRepository repository() => OrderRepository(
    ApiClient(
      client: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    ),
  );

  List<String?> get tabs => [
    for (final request in requests)
      if (request.url.path == '/api/orders') request.url.queryParameters['tab'],
  ];
}

Future<_Server> _open(
  WidgetTester tester,
  http.Response Function(http.Request request) respond, {
  Size size = const Size(800, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final server = _Server(respond);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: OrdersPage()),
      ),
      GoRoute(
        path: AppRoutes.orderDetails,
        builder: (context, state) => OrderDetailsPage(
          orderId: state.pathParameters['id']!,
          initial: state.extra as Order?,
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    Provider<OrderRepository>(
      create: (_) => server.repository(),
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

http.Response _page(
  List<Map<String, dynamic>> orders, {
  bool hasMore = false,
}) => jsonResponse({'orders': orders, 'hasMore': hasMore});

void main() {
  testWidgets('shows the title, tabs and each order on a card', (tester) async {
    await _open(tester, (_) => _page([_order('o1')]));

    expect(find.text('My Orders'), findsOneWidget);
    expect(find.text('View all your orders.'), findsOneWidget);
    for (final tab in ['All', 'Upcoming', 'History']) {
      expect(find.text(tab), findsOneWidget);
    }

    expect(find.text('Today'), findsOneWidget);

    final card = find.byKey(const ValueKey('order-card-o1'));
    Finder inCard(String text) =>
        find.descendant(of: card, matching: find.text(text));
    expect(inCard('Nasi Lemak'), findsOneWidget);
    expect(inCard('Warung Pak Din'), findsOneWidget);
    expect(inCard('Quantity: 2'), findsOneWidget);
    expect(inCard('RM 9.00'), findsOneWidget);
    expect(inCard('Pending'), findsOneWidget);
    expect(inCard('Total'), findsOneWidget);
    // The address and payment line sit on the Info page now, not the card.
    expect(inCard('Arked Meranti'), findsNothing);
    expect(inCard('Payment: Pay at pickup'), findsNothing);
  });

  testWidgets('a date header groups consecutive orders from the same day', (
    tester,
  ) async {
    await _open(
      tester,
      (_) => _page([
        _order('o1', item: 'First today', daysAgo: 0),
        _order('o2', item: 'Second today', daysAgo: 0),
        _order('o3', item: 'From yesterday', daysAgo: 1),
      ]),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    final today = tester.getTopLeft(find.text('Today')).dy;
    final firstToday = tester.getTopLeft(find.text('First today')).dy;
    final secondToday = tester.getTopLeft(find.text('Second today')).dy;
    final yesterday = tester.getTopLeft(find.text('Yesterday')).dy;
    final fromYesterday = tester.getTopLeft(find.text('From yesterday')).dy;
    expect(today, lessThan(firstToday));
    expect(firstToday, lessThan(secondToday));
    expect(secondToday, lessThan(yesterday));
    expect(yesterday, lessThan(fromYesterday));
  });

  testWidgets('an Older or Later bucket collapses behind a summary card', (
    tester,
  ) async {
    await _open(
      tester,
      (_) => _page([
        _order('o1', item: 'Old one', daysAgo: 10),
        _order('o2', item: 'Old two', daysAgo: 12),
      ]),
    );

    expect(find.text('Older'), findsOneWidget);
    expect(find.text('2 orders'), findsOneWidget);
    expect(find.text('Old one'), findsNothing);
    expect(find.text('Old two'), findsNothing);

    await tester.tap(find.text('2 orders'));
    await tester.pumpAndSettle();

    expect(find.text('2 orders'), findsNothing);
    expect(find.text('Old one'), findsOneWidget);
    expect(find.text('Old two'), findsOneWidget);
  });

  testWidgets('each tab asks the server for its own orders', (tester) async {
    final server = await _open(tester, (request) {
      final tab = request.url.queryParameters['tab'];
      if (tab == 'history') {
        return _page([
          _order('h1', item: 'Ended', endsInHours: -1),
          _order('h2', item: 'Cancelled one', status: 'cancelled'),
          _order('h3', item: 'Collected', status: 'completed'),
        ]);
      }
      return _page([_order('u1', item: 'Coming up')]);
    });

    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    expect(find.text('Coming up'), findsOneWidget);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Coming up'), findsNothing);
    expect(find.text('Pickup Ended'), findsOneWidget);
    expect(
      find.text('Cancelled'),
      findsNWidgets(2),
      reason: 'view chip and status chip',
    );
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);

    expect(server.tabs, ['all', 'upcoming', 'history']);
  });

  testWidgets('every tab has its own empty message', (tester) async {
    await _open(tester, (_) => _page([]));

    expect(find.text('No orders yet'), findsOneWidget);
    await tester.tap(find.text('Upcoming'));
    await tester.pumpAndSettle();
    expect(find.text('No upcoming orders'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('No past orders'), findsOneWidget);
  });

  testWidgets('a failed load offers Try Again', (tester) async {
    var fail = true;
    await _open(
      tester,
      (_) => fail
          ? jsonResponse({'error': 'Something went wrong.'}, 500)
          : _page([_order('o1')]),
    );

    expect(find.text('Try Again'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('order-card-o1')), findsOneWidget);
  });

  testWidgets('scrolling loads the next page without repeats', (tester) async {
    final server = await _open(tester, (request) {
      final page = request.url.queryParameters['page'];
      if (page == '1') {
        return _page([
          for (var i = 0; i < 20; i++) _order('a$i', item: 'First $i'),
        ], hasMore: true);
      }
      return _page([_order('b0', item: 'Second page')]);
    });

    await tester.scrollUntilVisible(
      find.text('Second page'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Second page'), findsOneWidget);
    final pages = [
      for (final request in server.requests)
        request.url.queryParameters['page'],
    ];
    expect(pages, ['1', '2']);
  });

  testWidgets('tapping a card opens the order details', (tester) async {
    final server = await _open(tester, (request) {
      if (request.url.path == '/api/orders/o1') {
        return jsonResponse({'order': _order('o1')});
      }
      return _page([_order('o1')]);
    });

    await tester.tap(find.byKey(const ValueKey('order-card-o1')));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailsPage), findsOneWidget);
    final banner = find.byKey(const ValueKey('order-status-banner'));
    expect(
      find.descendant(of: banner, matching: find.text('Pending')),
      findsOneWidget,
    );
    for (final text in [
      'Warung Pak Din',
      'Arked Meranti',
      'RM 4.50',
      'RM 9.00',
      'Pay at Pickup',
      'Price Per Item',
      'Payment Method',
      '2',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('Directions'), findsNothing);
    expect(find.text('Cancel Order'), findsNothing);
    expect(
      server.requests.map((request) => request.url.path),
      contains('/api/orders/o1'),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('My Orders'), findsOneWidget);
    expect(server.tabs.length, 2, reason: 'the list refreshes on return');
  });

  testWidgets('details for an order that cannot be found say so', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _Server(
      (_) => jsonResponse({'error': "We couldn't find this order."}, 404),
    );

    await tester.pumpWidget(
      Provider<OrderRepository>(
        create: (_) => server.repository(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: const OrderDetailsPage(orderId: 'missing'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("We couldn't find this order."), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });

  testWidgets('the customer Orders tab opens My Orders', (tester) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(token: 'saved'),
      onRequest: (request) async {
        if (request.url.path == '/api/orders') {
          return _page([_order('o1')]);
        }
        return jsonResponse({'user': userJson});
      },
    );

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();

    expect(find.text('My Orders'), findsOneWidget);
    expect(find.byKey(const ValueKey('order-card-o1')), findsOneWidget);
  });
}
