import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/pages/food_details_page.dart';
import 'package:savespoon/features/orders/data/order_repository.dart';
import 'package:savespoon/features/orders/domain/order.dart';

import 'helpers.dart';

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Map<String, dynamic> _listing({
  int stock = 3,
  int sold = 0,
  int endsInHours = 3,
  String status = 'active',
}) => {
  '_id': 'l1',
  'title': 'Nasi Lemak',
  'description': 'With sambal',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': stock,
  'soldCount': sold,
  'pickupStart': _inHours(endsInHours - 2),
  'pickupEnd': _inHours(endsInHours),
  'allergens': const ['egg'],
  'otherAllergens': const <String>[],
  'status': status,
  'stallName': 'Warung Pak Din',
  'pickupAddress': 'Cafeteria A, UTM Skudai',
};

Map<String, dynamic> _order() => {
  '_id': 'o1',
  'itemName': 'Nasi Lemak',
  'stallName': 'Warung Pak Din',
  'pickupAddress': 'Cafeteria A, UTM Skudai',
  'quantity': 2,
  'totalPrice': 9,
  'pickupStart': _inHours(1),
  'pickupEnd': _inHours(3),
  'status': 'pending',
};

http.Response _problem(int status, String code, String error) =>
    jsonResponse({'code': code, 'error': error}, status);

class _Harness {
  final List<Map<String, dynamic>> orderBodies = [];
  final List<List<Order>> placed = [];
  final List<int> added = [];
  String? popped;
}

Future<_Harness> _open(
  WidgetTester tester, {
  Map<String, dynamic>? listing,
  http.Response Function(_Harness harness)? onOrder,
  http.Response? onDetails,
  Future<String> Function()? onAdd,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final harness = _Harness();
  final api = ApiClient(
    client: MockClient((request) async {
      if (request.method == 'GET') {
        return onDetails ?? jsonResponse({'listing': listing ?? _listing()});
      }
      harness.orderBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (onOrder != null) return onOrder(harness);
      return jsonResponse({'order': _order()}, 201);
    }),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ListingRepository>(create: (_) => ListingRepository(api)),
        Provider<OrderRepository>(create: (_) => OrderRepository(api)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  harness.popped = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => FoodDetailsPage(
                        listingId: 'l1',
                        onAddToCart: (context, id, quantity) async {
                          harness.added.add(quantity);
                          return onAdd == null
                              ? 'Added 2 x Nasi Lemak to your cart.'
                              : onAdd();
                        },
                        onOrdered: (context, orders) =>
                            harness.placed.add(orders),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _confirmOrder(WidgetTester tester) async {
  await tester.tap(find.text('Order Now'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

String _total(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('details-total'))).data!;

void main() {
  testWidgets('shows the food details', (tester) async {
    await _open(tester);

    for (final text in [
      'Warung Pak Din',
      'Nasi Lemak',
      'With sambal',
      'RM 4.50',
      'RM 8.00',
      'Save 44%',
      'Rice',
      'Yes',
      'Egg',
      'Cafeteria A, UTM Skudai',
      '3 left',
      'Order Now',
      'Add to Cart',
    ]) {
      expect(find.textContaining(text), findsWidgets, reason: text);
    }
  });

  testWidgets('quantity stays between 1 and the stock left, and updates the '
      'total', (tester) async {
    await _open(tester);

    expect(_total(tester), 'RM 4.50');
    await tester.tap(find.byTooltip('Less'), warnIfMissed: false);
    await tester.pump();
    expect(_total(tester), 'RM 4.50');

    for (var index = 0; index < 5; index++) {
      await tester.tap(find.byTooltip('More'), warnIfMissed: false);
      await tester.pump();
    }
    expect(_total(tester), 'RM 13.50');
  });

  testWidgets('Order Now confirms the summary before placing', (tester) async {
    final harness = await _open(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.tap(find.text('Order Now'));
    await tester.pumpAndSettle();

    expect(find.text('2 x Nasi Lemak'), findsOneWidget);
    expect(find.text('Pay at pickup'), findsOneWidget);
    expect(find.textContaining('Pickup: Today'), findsOneWidget);
    expect(harness.orderBodies, isEmpty);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(harness.orderBodies, isEmpty);

    await _confirmOrder(tester);

    expect(harness.orderBodies.single.keys, {
      'listingId',
      'quantity',
      'requestId',
    });
    expect(harness.orderBodies.single['listingId'], 'l1');
    expect(harness.orderBodies.single['quantity'], 2);
    expect(harness.placed.single.single.itemName, 'Nasi Lemak');
  });

  testWidgets('the confirmation names the stall and address and shows the '
      'total in green', (tester) async {
    await _open(tester);

    await tester.tap(find.text('Order Now'));
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Warung Pak Din')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Cafeteria A, UTM Skudai'),
      ),
      findsOneWidget,
    );
    final total = tester.widget<Text>(
      find.byKey(const ValueKey('confirm-total')),
    );
    final context = tester.element(dialog);
    expect(total.data, 'RM 4.50');
    expect(total.style?.color, Theme.of(context).colorScheme.primary);
  });

  testWidgets('the quantity can be typed with the keypad', (tester) async {
    await _open(tester);

    final field = find.byKey(const ValueKey('quantity-field'));
    expect(tester.widget<TextField>(field).keyboardType, TextInputType.number);
    await tester.enterText(field, '3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(_total(tester), 'RM 13.50');
  });

  testWidgets('a typed quantity above the stock is refused', (tester) async {
    await _open(tester);

    final field = find.byKey(const ValueKey('quantity-field'));
    await tester.enterText(field, '9');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Enter a number from 1 to 3.'), findsOneWidget);
    expect(_total(tester), 'RM 4.50');
    expect(tester.widget<TextField>(field).controller!.text, '1');
  });

  testWidgets('a lost connection retries with the same request ID', (
    tester,
  ) async {
    var attempts = 0;
    final harness = await _open(
      tester,
      onOrder: (_) {
        attempts++;
        return attempts == 1
            ? jsonResponse({'error': 'x'}, 500)
            : jsonResponse({'order': _order()}, 200);
      },
    );

    await _confirmOrder(tester);
    expect(
      find.text("We couldn't place your order. Please try again."),
      findsOneWidget,
    );
    expect(harness.placed, isEmpty);

    await _confirmOrder(tester);
    expect(
      harness.orderBodies[0]['requestId'],
      harness.orderBodies[1]['requestId'],
    );
    expect(harness.placed, hasLength(1));
  });

  testWidgets('changing the quantity after a failure uses a new request ID', (
    tester,
  ) async {
    final harness = await _open(
      tester,
      onOrder: (_) => jsonResponse({'error': 'x'}, 500),
    );

    await _confirmOrder(tester);
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await _confirmOrder(tester);

    expect(
      harness.orderBodies[0]['requestId'],
      isNot(harness.orderBodies[1]['requestId']),
    );
  });

  testWidgets('not enough stock stays, shows the message and lowers the '
      'quantity', (tester) async {
    var detailsCalls = 0;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          detailsCalls++;
          return jsonResponse({
            'listing': _listing(stock: detailsCalls == 1 ? 3 : 1),
          });
        }
        return _problem(
          409,
          'NOT_ENOUGH_STOCK',
          'Only 1 Nasi Lemak left. Choose 1 or fewer and try again.',
        );
      }),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ListingRepository>(create: (_) => ListingRepository(api)),
          Provider<OrderRepository>(create: (_) => OrderRepository(api)),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: FoodDetailsPage(
            listingId: 'l1',
            onAddToCart: (context, id, quantity) async => '',
            onOrdered: (context, orders) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pump();

    await _confirmOrder(tester);

    expect(
      find.text('Only 1 Nasi Lemak left. Choose 1 or fewer and try again.'),
      findsOneWidget,
    );
    expect(find.text('1 left'), findsOneWidget);
    expect(_total(tester), 'RM 4.50');
  });

  for (final (code, message) in [
    ('SOLD_OUT', 'Sorry, Nasi Lemak has just sold out.'),
    ('PICKUP_ENDED', 'Pickup for Nasi Lemak has ended.'),
    ('LISTING_GONE', 'This item is no longer available.'),
  ]) {
    testWidgets('$code returns to the previous screen with its message', (
      tester,
    ) async {
      final harness = await _open(
        tester,
        onOrder: (_) =>
            _problem(code == 'LISTING_GONE' ? 404 : 409, code, message),
      );

      await _confirmOrder(tester);

      expect(find.byType(FoodDetailsPage), findsNothing);
      expect(harness.popped, message);
    });
  }

  testWidgets('a sold-out listing leaves as soon as it opens', (tester) async {
    final harness = await _open(tester, listing: _listing(stock: 0));

    expect(find.byType(FoodDetailsPage), findsNothing);
    expect(harness.popped, 'Sorry, Nasi Lemak has just sold out.');
  });

  testWidgets('a closed listing leaves as soon as it opens', (tester) async {
    final harness = await _open(tester, listing: _listing(endsInHours: -1));

    expect(harness.popped, 'Pickup for Nasi Lemak has ended.');
  });

  testWidgets('a deleted listing leaves as soon as it opens', (tester) async {
    final harness = await _open(
      tester,
      onDetails: _problem(
        404,
        'LISTING_GONE',
        'This item is no longer available.',
      ),
    );

    expect(harness.popped, 'This item is no longer available.');
  });

  testWidgets('a connection error on opening offers Try again', (tester) async {
    await _open(tester, onDetails: jsonResponse({'error': 'Server down'}, 500));

    expect(find.text('Server down'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('Add to Cart sends the quantity and shows the message', (
    tester,
  ) async {
    final harness = await _open(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    await tester.tap(find.text('Add to Cart'));
    await tester.pumpAndSettle();

    expect(harness.added, [2]);
    expect(find.text('Added 2 x Nasi Lemak to your cart.'), findsOneWidget);
    expect(find.byType(FoodDetailsPage), findsOneWidget);
  });

  testWidgets('Add to Cart failing shows its own message', (tester) async {
    await _open(tester, onAdd: () => throw const ApiException('offline'));

    await tester.tap(find.text('Add to Cart'));
    await tester.pumpAndSettle();

    expect(
      find.text("We couldn't add this to your cart. Please try again."),
      findsOneWidget,
    );
  });

  group('Selling Fast', () {
    final now = DateTime.now();
    ListingBadge? badge({
      required int stock,
      required int sold,
      int endsInHours = 3,
    }) => Listing.fromJson(
      _listing(stock: stock, sold: sold, endsInHours: endsInHours),
    ).badgeAt(now);

    test('shows with 3 sold, 30% sold and more than 5 left', () {
      expect(badge(stock: 7, sold: 3), ListingBadge.sellingFast);
    });

    test('needs at least 3 sold', () {
      expect(badge(stock: 6, sold: 2), isNot(ListingBadge.sellingFast));
    });

    test('needs at least 30% sold', () {
      expect(badge(stock: 20, sold: 3), isNot(ListingBadge.sellingFast));
    });

    test('Only N left comes first', () {
      expect(badge(stock: 5, sold: 10), ListingBadge.lowStock);
    });

    test('comes before Ending Soon', () {
      final closing = DateTime.now().add(const Duration(minutes: 30));
      ListingBadge? badgeWithSold(int sold) =>
          Listing.fromJson(_listing(stock: 7, sold: sold, endsInHours: 1))
              .badgeAt(closing);

      expect(badgeWithSold(0), ListingBadge.endingSoon);
      expect(badgeWithSold(3), ListingBadge.sellingFast);
    });

    test('a listing with no sales count shows no ribbon for it', () {
      final json = _listing(stock: 10)..remove('soldCount');
      expect(Listing.fromJson(json).soldCount, 0);
    });
  });
}
