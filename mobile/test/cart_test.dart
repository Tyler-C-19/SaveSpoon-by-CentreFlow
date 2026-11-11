import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/core/widgets/auto_refresh.dart';
import 'package:savespoon/features/cart/data/cart_repository.dart';
import 'package:savespoon/features/cart/presentation/pages/cart_page.dart';
import 'package:savespoon/features/cart/presentation/providers/cart_provider.dart';
import 'package:savespoon/features/listings/presentation/pages/customer_home_page.dart';
import 'package:savespoon/features/listings/presentation/pages/food_details_page.dart';
import 'package:savespoon/features/orders/domain/order.dart';
import 'package:savespoon/features/orders/presentation/pages/order_confirmation_page.dart';

import 'helpers.dart';

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Map<String, dynamic> _item({
  String id = 'l1',
  String name = 'Nasi Lemak',
  String stall = 'First Stall',
  int quantity = 1,
  double lineTotal = 4.5,
  int stock = 5,
  List<String> notices = const [],
}) => {
  'listingId': id,
  'itemName': name,
  'stallName': stall,
  'quantity': quantity,
  'unitPrice': 4.5,
  'lineTotal': lineTotal,
  'available': true,
  'reason': null,
  'notices': notices,
  'category': 'Rice',
  'pickupAddress': 'Cafeteria A',
  'stockLeft': stock,
  'pickupStart': _inHours(1),
  'pickupEnd': _inHours(3),
};

Map<String, dynamic> _unavailable({
  String id = 'l9',
  String name = 'Old Kuih',
  String reason = 'Sold out',
}) => {
  'listingId': id,
  'itemName': name,
  'stallName': 'First Stall',
  'quantity': 1,
  'unitPrice': 2,
  'lineTotal': 0,
  'available': false,
  'reason': reason,
  'notices': const <String>[],
};

Map<String, dynamic> _cart(
  List<Map<String, dynamic>> items, {
  double total = 4.5,
  List<String> warnings = const [],
}) => {
  'cart': {'items': items, 'total': total, 'warnings': warnings},
};

final _emptyCart = _cart(const [], total: 0);

Map<String, dynamic> _order(String id) => {
  '_id': id,
  'itemName': 'Nasi Lemak',
  'stallName': 'First Stall',
  'pickupAddress': 'Cafeteria A',
  'quantity': 1,
  'totalPrice': 4.5,
  'pickupStart': _inHours(1),
  'pickupEnd': _inHours(3),
  'status': 'pending',
  'category': 'Rice',
};

class _Harness {
  final List<http.Request> requests = [];
  final List<List<Order>> placed = [];
}

Future<_Harness> _open(
  WidgetTester tester,
  http.Response Function(http.Request request) respond,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final harness = _Harness();
  final api = ApiClient(
    client: MockClient((request) async {
      harness.requests.add(request);
      return respond(request);
    }),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<CartProvider>(
      create: (_) => CartProvider(CartRepository(api)),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CartPage(
            onOrdered: (context, orders) => harness.placed.add(orders),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('an empty cart says so', (tester) async {
    await _open(tester, (_) => jsonResponse(_emptyCart));

    expect(find.text('My Cart'), findsOneWidget);
    expect(find.text('Your cart is empty'), findsOneWidget);
    expect(find.text('Place Order'), findsNothing);
    expect(find.text('Clear Cart'), findsNothing);
  });

  testWidgets('an item shows its picture, location and a red remove icon', (
    tester,
  ) async {
    await _open(tester, (_) => jsonResponse(_cart([_item()])));

    expect(find.byIcon(Icons.rice_bowl_rounded), findsOneWidget);
    expect(find.text('Cafeteria A'), findsOneWidget);

    final remove = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    final context = tester.element(find.byType(IconButton).first);
    expect(remove.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('a failed load offers Try again', (tester) async {
    await _open(tester, (_) => jsonResponse({'error': 'Server down'}, 500));

    expect(find.text('Server down'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('items are grouped by stall with the held notice and warnings', (
    tester,
  ) async {
    await _open(
      tester,
      (_) => jsonResponse(
        _cart(
          [_item(), _item(id: 'l2', name: 'Roti Canai', stall: 'Second Stall')],
          total: 9,
          warnings: [
            "Heads up: you'll collect from 2 stalls, up to 0.8 km apart.",
          ],
        ),
      ),
    );

    expect(find.text('From First Stall'), findsOneWidget);
    expect(find.text('From Second Stall'), findsOneWidget);
    expect(
      find.text("Items aren't held until you place your order."),
      findsOneWidget,
    );
    expect(
      find.text("Heads up: you'll collect from 2 stalls, up to 0.8 km apart."),
      findsOneWidget,
    );
    expect(find.text('Clear Cart'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      'RM 9.00',
    );
  });

  testWidgets('unavailable items show a reason and can be removed together', (
    tester,
  ) async {
    final harness = await _open(tester, (request) {
      if (request.method == 'DELETE') return jsonResponse(_cart([_item()]));
      return jsonResponse(_cart([_item(), _unavailable()]));
    });

    expect(find.text('Sold out'), findsOneWidget);

    await tester.tap(find.text('Remove unavailable items'));
    await tester.pumpAndSettle();

    expect(harness.requests.last.url.path, '/api/cart/unavailable');
    expect(find.text('Old Kuih'), findsNothing);
    expect(find.text('Remove unavailable items'), findsNothing);
  });

  testWidgets('only unavailable items means nothing can be ordered', (
    tester,
  ) async {
    await _open(tester, (_) => jsonResponse(_cart([_unavailable()], total: 0)));

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('notices for a lowered quantity or changed price show', (
    tester,
  ) async {
    await _open(
      tester,
      (_) => jsonResponse(
        _cart([
          _item(notices: ['Price changed from RM 3.00 to RM 4.50.']),
        ]),
      ),
    );

    expect(find.text('Price changed from RM 3.00 to RM 4.50.'), findsOneWidget);
  });

  testWidgets('changing a quantity updates the cart', (tester) async {
    final harness = await _open(tester, (request) {
      if (request.method == 'PATCH') {
        return jsonResponse(
          _cart([_item(quantity: 2, lineTotal: 9)], total: 9),
        );
      }
      return jsonResponse(_cart([_item()]));
    });

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    final patch = harness.requests.last;
    expect(patch.url.path, '/api/cart/items/l1');
    expect(jsonDecode(patch.body), {'quantity': 2});
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      'RM 9.00',
    );
  });

  testWidgets('removing an available item asks first', (tester) async {
    final harness = await _open(tester, (request) {
      if (request.method == 'DELETE') return jsonResponse(_emptyCart);
      return jsonResponse(_cart([_item()]));
    });

    await tester.tap(find.byTooltip('Remove Nasi Lemak'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this item?'), findsOneWidget);
    await tester.tap(find.text('Keep item'));
    await tester.pumpAndSettle();
    expect(harness.requests.where((r) => r.method == 'DELETE'), isEmpty);
    expect(find.text('Nasi Lemak'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Nasi Lemak'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(harness.requests.last.url.path, '/api/cart/items/l1');
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('removing an unavailable item does not ask', (tester) async {
    final harness = await _open(tester, (request) {
      if (request.method == 'DELETE') return jsonResponse(_emptyCart);
      return jsonResponse(_cart([_unavailable()], total: 0));
    });

    await tester.tap(find.byTooltip('Remove Old Kuih'));
    await tester.pumpAndSettle();

    expect(find.text('Remove this item?'), findsNothing);
    expect(harness.requests.last.url.path, '/api/cart/items/l9');
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets('Clear Cart asks first', (tester) async {
    final harness = await _open(tester, (request) {
      if (request.method == 'DELETE') return jsonResponse(_emptyCart);
      return jsonResponse(_cart([_item()]));
    });

    await tester.tap(find.text('Clear Cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep items'));
    await tester.pumpAndSettle();
    expect(harness.requests.where((r) => r.method == 'DELETE'), isEmpty);

    await tester.tap(find.text('Clear Cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(harness.requests.last.method, 'DELETE');
    expect(harness.requests.last.url.path, '/api/cart');
  });

  Future<void> placeOrder(WidgetTester tester) async {
    await tester.tap(find.text('Place Order'));
    await tester.pumpAndSettle();
    expect(find.text('Pay at pickup'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
  }

  testWidgets('checkout sends the shown total and hands back the orders', (
    tester,
  ) async {
    var done = false;
    final harness = await _open(tester, (request) {
      if (request.url.path.endsWith('/checkout')) {
        done = true;
        return jsonResponse({
          'orders': [_order('o1')],
        }, 201);
      }
      return jsonResponse(
        done
            ? _cart([_unavailable()], total: 0)
            : _cart([_item(), _unavailable()]),
      );
    });

    await placeOrder(tester);

    final checkout = harness.requests.firstWhere(
      (r) => r.url.path.endsWith('/checkout'),
    );
    final body = jsonDecode(checkout.body) as Map<String, dynamic>;
    expect(body['expectedTotal'], 4.5);
    expect(body['requestId'], isNotEmpty);
    expect(harness.placed.single.single.id, 'o1');
  });

  testWidgets('a changed cart reloads with the message and places nothing', (
    tester,
  ) async {
    var checkedOut = false;
    final harness = await _open(tester, (request) {
      if (request.url.path.endsWith('/checkout')) {
        checkedOut = true;
        return jsonResponse({
          'code': 'CART_CHANGED',
          'error': 'Your cart changed. The new total is RM 9.00. Check it and try again.',
        }, 409);
      }
      return checkedOut
          ? jsonResponse(_cart([_item(quantity: 2, lineTotal: 9)], total: 9))
          : jsonResponse(_cart([_item()]));
    });

    await placeOrder(tester);

    expect(
      find.text(
        'Your cart changed. The new total is RM 9.00. Check it and try again.',
      ),
      findsOneWidget,
    );
    expect(harness.placed, isEmpty);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('cart-total'))).data,
      'RM 9.00',
    );
  });

  testWidgets('a server failure retries with the same request ID', (
    tester,
  ) async {
    var attempts = 0;
    final harness = await _open(tester, (request) {
      if (request.url.path.endsWith('/checkout')) {
        attempts++;
        return attempts == 1
            ? jsonResponse({'error': 'x'}, 500)
            : jsonResponse({
                'orders': [_order('o1')],
              });
      }
      return jsonResponse(_cart([_item()]));
    });

    await placeOrder(tester);
    expect(
      find.text("We couldn't place your order. Please try again."),
      findsOneWidget,
    );
    await placeOrder(tester);

    final ids = [
      for (final request in harness.requests)
        if (request.url.path.endsWith('/checkout'))
          (jsonDecode(request.body) as Map<String, dynamic>)['requestId'],
    ];
    expect(ids, hasLength(2));
    expect(ids[0], ids[1]);
    expect(harness.placed, hasLength(1));
  });

  testWidgets('resetting the cart forgets the last account and ignores a late '
      'response', (tester) async {
    final api = ApiClient(
      client: MockClient((_) async => jsonResponse(_cart([_item()]))),
    );
    final provider = CartProvider(CartRepository(api));
    addTearDown(provider.dispose);

    await provider.refresh();
    expect(provider.count, 1);

    final late = provider.refresh();
    provider.reset();
    await late;

    expect(provider.count, 0);
    expect(provider.cart, isNull);
  });

  group('whole app', () {
    final listing = {
      '_id': 'l1',
      'title': 'Nasi Lemak',
      'category': 'Rice',
      'isHalal': true,
      'originalPrice': 8,
      'discountedPrice': 4.5,
      'quantityAvailable': 7,
      'soldCount': 3,
      'pickupStart': _inHours(1),
      'pickupEnd': _inHours(3),
      'allergens': const <String>[],
      'otherAllergens': const <String>[],
      'status': 'active',
      'stallName': 'First Stall',
      'pickupAddress': 'Cafeteria A',
    };

    FakeTokenStorage customer() =>
        FakeTokenStorage(token: 't', userJson: jsonEncode(userJson));

    http.Response common(http.Request request) {
      final path = request.url.path;
      if (path == '/api/auth/me') return jsonResponse({'user': userJson});
      if (path == '/api/listings') {
        return jsonResponse({
          'listings': [listing],
          'hasMore': false,
        });
      }
      if (path == '/api/listings/running-out') {
        return jsonResponse({'listings': []});
      }
      if (path == '/api/listings/l1') {
        return jsonResponse({'listing': listing});
      }
      return jsonResponse(_cart([_item()]));
    }

    testWidgets(
      'tapping a card opens details, and the Cart tab shows a count',
      (tester) async {
        await startApp(
          tester,
          storage: customer(),
          stubBrowse: false,
          onRequest: (request) async => common(request),
        );
        await tester.pumpAndSettle();

        expect(find.text('Selling Fast'), findsOneWidget);
        expect(find.widgetWithText(Badge, '1'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('listing-card-l1')));
        await tester.pumpAndSettle();

        expect(find.byType(FoodDetailsPage), findsOneWidget);
        expect(find.text('Cafeteria A'), findsOneWidget);
      },
    );

    testWidgets('ordering shows the confirmation, then returns to a refreshed '
        'Home', (tester) async {
      var browseCalls = 0;
      await startApp(
        tester,
        storage: customer(),
        stubBrowse: false,
        onRequest: (request) async {
          if (request.url.path == '/api/orders') {
            return jsonResponse({'order': _order('o1')}, 201);
          }
          if (request.url.path == '/api/listings') browseCalls++;
          return common(request);
        },
      );
      await tester.pumpAndSettle();
      final callsBefore = browseCalls;

      await tester.tap(find.byKey(const ValueKey('listing-card-l1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Order Now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderConfirmationPage), findsOneWidget);
      expect(find.byKey(const ValueKey('order-placed-tick')), findsOneWidget);
      expect(find.byIcon(Icons.rice_bowl_rounded), findsOneWidget);
      expect(find.text('Order placed!'), findsOneWidget);
      expect(find.text('Cafeteria A'), findsOneWidget);
      expect(browseCalls, greaterThan(callsBefore));

      await tester.tap(find.text('Back to Home'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderConfirmationPage), findsNothing);
      expect(find.byType(FoodDetailsPage), findsNothing);
      expect(find.textContaining('Welcome back'), findsOneWidget);
    });

    testWidgets('Home refreshes itself while it is on screen', (tester) async {
      var browseCalls = 0;
      await startApp(
        tester,
        storage: customer(),
        stubBrowse: false,
        onRequest: (request) async {
          if (request.url.path == '/api/listings') browseCalls++;
          return common(request);
        },
      );
      await tester.pumpAndSettle();
      final before = browseCalls;

      await tester.pump(AutoRefresh.interval);
      await tester.pumpAndSettle();
      expect(browseCalls, before + 1);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.pump(AutoRefresh.interval);
      await tester.pumpAndSettle();
      expect(browseCalls, before + 1);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(browseCalls, before + 2);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(browseCalls, before + 3);
    });

    testWidgets('an unavailable item returns Home with a message', (
      tester,
    ) async {
      await startApp(
        tester,
        storage: customer(),
        stubBrowse: false,
        onRequest: (request) async {
          if (request.url.path == '/api/listings/l1') {
            return jsonResponse({
              'code': 'LISTING_GONE',
              'error': 'This item is no longer available.',
            }, 404);
          }
          return common(request);
        },
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('listing-card-l1')));
      await tester.pumpAndSettle();

      expect(find.byType(FoodDetailsPage), findsNothing);
      expect(find.text('This item is no longer available.'), findsOneWidget);
    });

    testWidgets('logging out clears the cart', (tester) async {
      await startApp(
        tester,
        storage: customer(),
        stubBrowse: false,
        onRequest: (request) async => common(request),
      );
      await tester.pumpAndSettle();
      final home = tester.element(find.byType(CustomerHomePage));
      final cart = home.read<CartProvider>();
      expect(cart.count, 1);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(cart.count, 0);
    });
  });
}
