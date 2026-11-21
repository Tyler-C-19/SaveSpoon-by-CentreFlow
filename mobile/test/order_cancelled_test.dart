import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/orders/domain/order.dart';
import 'package:savespoon/features/orders/presentation/pages/order_cancelled_page.dart';

import 'order_repository_test.dart' show orderJson;

Order _order(String id, String item, {String status = 'cancelled'}) =>
    Order.fromJson({...orderJson(id: id, status: status), 'itemName': item});

Future<List<BuildContext>> _open(
  WidgetTester tester, {
  required List<Order> cancelled,
  List<Order> skipped = const [],
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final done = <BuildContext>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OrderCancelledPage(
        cancelled: cancelled,
        skipped: skipped,
        onDone: done.add,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return done;
}

void main() {
  testWidgets('shows the cancelled order with the red X', (tester) async {
    final done = await _open(tester, cancelled: [_order('a', 'Nasi Lemak')]);

    expect(find.byKey(const ValueKey('order-cancelled-mark')), findsOneWidget);
    expect(find.text('Order Cancelled'), findsOneWidget);
    expect(
      find.text('No payment was taken, as this order was pay at pickup.'),
      findsOneWidget,
    );
    expect(find.text('2 x Nasi Lemak'), findsOneWidget);
    expect(find.text('Warung Pak Din'), findsOneWidget);
    expect(find.text('Still Ordered'), findsNothing);

    await tester.tap(find.text('Back to My Orders'));
    expect(done, hasLength(1));
  });

  testWidgets('lists every cancelled order and the ones still ordered', (
    tester,
  ) async {
    await _open(
      tester,
      cancelled: [_order('a', 'Nasi Lemak'), _order('b', 'Kuih')],
      skipped: [_order('c', 'Teh Tarik', status: 'pending')],
    );

    expect(find.text('Orders Cancelled'), findsOneWidget);
    expect(
      find.textContaining('these orders were pay at pickup'),
      findsOneWidget,
    );
    expect(find.text('2 x Nasi Lemak'), findsOneWidget);
    expect(find.text('2 x Kuih'), findsOneWidget);
    expect(find.text('Still Ordered'), findsOneWidget);
    expect(find.text('2 x Teh Tarik'), findsOneWidget);
  });
}
