// Every screen where a listing photo sits beside text, at several phone
// widths and text sizes. Flutter reports any overflow as an error, which
// fails the test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/cart/domain/cart.dart';
import 'package:savespoon/features/cart/presentation/widgets/cart_item_tile.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/pages/relist_page.dart';
import 'package:savespoon/features/listings/presentation/widgets/food_thumbnail.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_card.dart';
import 'package:savespoon/features/listings/presentation/widgets/search_result_row.dart';
import 'package:savespoon/features/orders/domain/order.dart';
import 'package:savespoon/features/orders/presentation/pages/order_confirmation_page.dart';

const _widths = [320.0, 360.0, 411.0];
const _textScales = [1.0, 1.3, 2.0];

const _shortName = 'Kuih';
const _longName = 'Roti Jala (3 pcs) with Curry and Extra Sambal on the Side';
const _longStall = 'Kafe Cendana Mamak and Western Food Corner';
const _longAddress =
    'Kiosk 3, Arked Meranti Food Court, Jalan Pendidikan, UTM Skudai, Johor';

final DateTime _now = DateTime.now();

String _time(Duration offset) => _now.add(offset).toUtc().toIso8601String();

Map<String, dynamic> _listingJson({
  String title = _longName,
  bool ended = false,
}) => {
  '_id': 'l1',
  'title': title,
  'description': 'Lacy net crepes with chicken curry',
  'category': 'Snacks',
  'isHalal': false,
  'originalPrice': 3.5,
  'discountedPrice': 2,
  'quantityAvailable': 4,
  'soldCount': 6,
  'pickupStart': _time(Duration(hours: ended ? -4 : -1)),
  'pickupEnd': _time(Duration(hours: ended ? -2 : 3)),
  'allergens': ['gluten', 'egg', 'milk', 'coconut'],
  'otherAllergens': ['belacan'],
  'status': 'active',
  'stallName': _longStall,
  'pickupAddress': _longAddress,
  'imageUrl': 'https://cdn/full.jpg',
  'imageThumbUrl': 'https://cdn/thumb.jpg',
};

Order _order({
  String name = _longName,
  String stall = _longStall,
  String? address = _longAddress,
}) => Order.fromJson({
  '_id': 'o1',
  'listing': 'l1',
  'itemName': name,
  'stallName': stall,
  'pickupAddress': ?address,
  'category': 'Snacks',
  'imageThumbUrl': 'https://cdn/thumb.jpg',
  'quantity': 12,
  'unitPrice': 2,
  'totalPrice': 24,
  'status': 'pending',
  'pickupStart': _time(const Duration(hours: 1)),
  'pickupEnd': _time(const Duration(hours: 8)),
});

CartItem _cartItem({bool available = true}) => CartItem.fromJson({
  'listingId': 'l1',
  'itemName': _longName,
  'stallName': _longStall,
  'quantity': 2,
  'unitPrice': 2,
  'lineTotal': 4,
  'available': available,
  'reason': available ? null : 'No longer available',
  'notices': ['Price changed from RM 2.50 to RM 2.00.'],
  'category': 'Snacks',
  'imageThumbUrl': 'https://cdn/thumb.jpg',
  'pickupAddress': _longAddress,
  'stockLeft': 4,
  'pickupStart': _time(const Duration(hours: 1)),
  'pickupEnd': _time(const Duration(hours: 3)),
});

// Pumps [child] at every width and text size, failing on any overflow.
Future<void> _everySize(
  WidgetTester tester,
  Widget Function() child, {
  double height = 1600,
}) async {
  for (final width in _widths) {
    for (final scale in _textScales) {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, height),
              textScaler: TextScaler.linear(scale),
            ),
            child: child(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      final error = tester.takeException();
      if (error != null) {
        final detail = error is FlutterError
            ? error.diagnostics.map((item) => '$item').join('\n')
            : '$error';
        fail('width $width, text x$scale: $detail');
      }
    }
  }
  tester.view.reset();
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget child, {
  double width = 411,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 1600),
          textScaler: TextScaler.linear(scale),
        ),
        child: child,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('the order price sits beside the name when there is room', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      OrderConfirmationPage(
        orders: [_order(name: 'Chicken Sandwich')],
        onDone: (_) {},
      ),
      // The test font is about twice as wide as a phone's.
      width: 600,
    );
    expect(find.byKey(const ValueKey('order-price-beside')), findsOneWidget);
    expect(find.byKey(const ValueKey('order-price-below')), findsNothing);
  });

  testWidgets('the order price moves under the name when space is tight', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      OrderConfirmationPage(orders: [_order()], onDone: (_) {}),
      width: 320,
      scale: 2,
    );
    expect(find.byKey(const ValueKey('order-price-below')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very long order name ends with an ellipsis after 3 lines', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      OrderConfirmationPage(
        orders: [_order(name: List.filled(12, _longName).join(' '))],
        onDone: (_) {},
      ),
      width: 320,
    );
    final name = tester.widget<Text>(find.textContaining('12 x Roti Jala'));
    expect(name.maxLines, 3);
    expect(name.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  for (final withPhoto in [true, false]) {
    testWidgets(
      'Relist Now ${withPhoto ? 'has a dark shade over a photo' : 'stays green without a photo'}',
      (tester) async {
        final json = _listingJson(ended: true);
        if (!withPhoto) {
          json
            ..remove('imageUrl')
            ..remove('imageThumbUrl');
        }
        await _pumpAt(
          tester,
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                height: ListingCard.browseHeight,
                child: ListingCard(
                  listing: Listing.fromJson(json),
                  onTap: () {},
                  onRelist: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.text('Relist Now'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('relist-now-shade')),
          withPhoto ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  testWidgets('Relist Now is drawn above the ribbons', (tester) async {
    await _pumpAt(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 180,
            height: ListingCard.browseHeight,
            child: ListingCard(
              listing: Listing.fromJson(_listingJson(ended: true)),
              onTap: () {},
              onRelist: () {},
            ),
          ),
        ),
      ),
    );
    final picture = find
        .ancestor(
          of: find.byKey(const ValueKey('card-relist')),
          matching: find.byType(Stack),
        )
        .first;
    // The ribbon shares the picture's layers, and Relist Now comes last.
    expect(
      find.descendant(
        of: picture,
        matching: find.text('Unlisted - Pickup Ended'),
      ),
      findsOneWidget,
    );
    expect(tester.widget<Stack>(picture).children.last, isA<Material>());
  });

  testWidgets('the cart address sits right under the item name', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      Scaffold(
        body: ListView(
          children: [
            CartItemTile(
              item: CartItem.fromJson({
                'listingId': 'l1',
                'itemName': 'Kuih',
                'stallName': 'Kafe',
                'quantity': 1,
                'unitPrice': 2,
                'lineTotal': 2,
                'available': true,
                'notices': <String>[],
                'pickupAddress': 'UTM',
                'stockLeft': 4,
                'pickupStart': _time(const Duration(hours: 1)),
                'pickupEnd': _time(const Duration(hours: 3)),
              }),
              onQuantityChanged: (_) {},
              onRemove: () {},
            ),
          ],
        ),
      ),
    );
    final name = tester.getRect(find.byKey(const ValueKey('cart-item-name')));
    final address = tester.getRect(find.text('UTM'));
    expect(address.top - name.bottom, lessThan(6));
    expect(find.byTooltip('Remove Kuih'), findsOneWidget);
  });

  testWidgets('food photos shown to read have no green border', (tester) async {
    await _pumpAt(
      tester,
      RelistPage(listing: Listing.fromJson(_listingJson(ended: true))),
    );
    expect(find.byKey(const ValueKey('photo-border')), findsNothing);
  });

  group('order confirmation', () {
    for (final (label, order) in [
      ('long name and address', _order()),
      ('short name, no address', _order(name: _shortName, address: null)),
    ]) {
      testWidgets('$label never overflows', (tester) async {
        await _everySize(
          tester,
          () => OrderConfirmationPage(orders: [order], onDone: (_) {}),
        );
      });
    }

    testWidgets('a checkout of several orders never overflows', (tester) async {
      await _everySize(
        tester,
        () => OrderConfirmationPage(
          orders: [
            _order(),
            _order(name: _shortName),
            _order(address: null),
          ],
          onDone: (_) {},
        ),
        height: 2400,
      );
    });

    testWidgets(
      'the photo stays 88 wide, at least square, and grows with the text',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Future<Size> photoFor(Order order) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: OrderConfirmationPage(orders: [order], onDone: (_) {}),
            ),
          );
          await tester.pump(const Duration(seconds: 2));
          return tester.getSize(find.byKey(const ValueKey('order-photo')));
        }

        final short = await photoFor(
          _order(name: _shortName, stall: 'Kafe', address: null),
        );
        expect(short.width, 88);
        expect(short.height, greaterThanOrEqualTo(88));
        final long = await photoFor(_order());
        expect(long.width, 88);
        expect(long.height, greaterThan(short.height));
      },
    );
  });

  testWidgets('a large photo never changes the photo column', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PhotoColumn(
                    key: ValueKey('column'),
                    width: 88,
                    // Stands in for a loaded 480 px photo.
                    child: SizedBox(width: 480, height: 480),
                  ),
                  Expanded(child: SizedBox(height: 120)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('column'))),
      const Size(88, 120),
    );
  });

  testWidgets('Relist Item summary never overflows', (tester) async {
    await _everySize(
      tester,
      () => RelistPage(listing: Listing.fromJson(_listingJson(ended: true))),
    );
  });

  for (final available in [true, false]) {
    testWidgets(
      'cart item (${available ? 'available' : 'unavailable'}) never overflows',
      (tester) async {
        await _everySize(
          tester,
          () => Scaffold(
            body: ListView(
              children: [
                CartItemTile(
                  item: _cartItem(available: available),
                  onQuantityChanged: (_) {},
                  onRemove: () {},
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  testWidgets('search result row with a photo never overflows', (tester) async {
    await _everySize(
      tester,
      () => Scaffold(
        body: ListView(
          children: [
            SearchResultRow(listing: Listing.fromJson(_listingJson())),
          ],
        ),
      ),
    );
  });

  testWidgets('an ended card with Relist Now never overflows its picture', (
    tester,
  ) async {
    await _everySize(
      tester,
      () => Scaffold(
        body: Center(
          child: SizedBox(
            width: 150,
            height: ListingCard.browseHeight,
            child: ListingCard(
              listing: Listing.fromJson(_listingJson(ended: true)),
              onTap: () {},
              onRelist: () {},
            ),
          ),
        ),
      ),
    );
  });
}
