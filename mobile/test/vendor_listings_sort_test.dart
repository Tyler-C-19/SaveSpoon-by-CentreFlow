import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/routing/app_router.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/pages/vendor_listings_page.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_card.dart';

import 'helpers.dart';

final DateTime _now = DateTime.now();

Map<String, dynamic> _json(
  String id, {
  int stock = 5,
  double price = 4,
  int sold = 0,
}) => {
  '_id': id,
  'title': 'Item $id',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 10,
  'discountedPrice': price,
  'quantityAvailable': stock,
  'soldCount': sold,
  'pickupStart': _now.toUtc().toIso8601String(),
  'pickupEnd': _now.add(const Duration(hours: 2)).toUtc().toIso8601String(),
  'allergens': <String>[],
  'status': 'active',
};

// Newest first, as the server sends them.
final List<Map<String, dynamic>> _mine = [
  _json('a', stock: 8, price: 5, sold: 1),
  _json('b', stock: 2, price: 3, sold: 9),
  _json('c', stock: 6, price: 4, sold: 9),
];

List<String> _ids(List<Listing> listings) => [for (final l in listings) l.id];

void main() {
  final listings = [for (final json in _mine) Listing.fromJson(json)];

  test('sorts by newest, low stock, pricing and popularity', () {
    expect(_ids(sortListings(listings, ListingSort.newest)), ['a', 'b', 'c']);
    expect(_ids(sortListings(listings, ListingSort.lowStock)), ['b', 'c', 'a']);
    expect(_ids(sortListings(listings, ListingSort.pricing)), ['b', 'c', 'a']);
    // Ties keep the newest first.
    expect(_ids(sortListings(listings, ListingSort.popularity)), [
      'b',
      'c',
      'a',
    ]);
    expect(_ids(listings), ['a', 'b', 'c']);
  });

  test('All shows just-relisted first, then listed, then unlisted', () {
    final mixed = [
      Listing.fromJson(_json('sold', stock: 0)),
      ...listings,
      Listing.fromJson({..._json('off'), 'status': 'paused'}),
    ];
    // Without relists: listed first, keeping the sort order inside each group.
    expect(_ids(prioritiseListings(mixed, {}, _now)), [
      'a',
      'b',
      'c',
      'sold',
      'off',
    ]);
    // A relisted item goes to the very top, even a turned-off one.
    expect(_ids(prioritiseListings(mixed, {'off', 'b'}, _now)), [
      'b',
      'off',
      'a',
      'c',
      'sold',
    ]);
  });

  test('Listed and Unlisted filters split by what customers can order', () {
    final mixed = [
      ...listings,
      Listing.fromJson(_json('sold', stock: 0)),
      Listing.fromJson({..._json('off'), 'status': 'paused'}),
    ];
    expect(_ids(filterListings(mixed, null, _now)), [
      'a',
      'b',
      'c',
      'sold',
      'off',
    ]);
    expect(_ids(filterListings(mixed, true, _now)), ['a', 'b', 'c']);
    expect(_ids(filterListings(mixed, false, _now)), ['sold', 'off']);
  });

  Future<List<String>> pumpTab(
    WidgetTester tester, {
    List<Map<String, dynamic>> Function()? mine,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final opened = <String>[];
    var loads = 0;
    final router = GoRouter(
      initialLocation: AppRoutes.vendorListings,
      routes: [
        GoRoute(
          path: AppRoutes.vendorListings,
          builder: (context, state) =>
              const Scaffold(body: VendorListingsPage()),
        ),
        GoRoute(
          path: AppRoutes.vendorListing,
          builder: (context, state) {
            opened.add(state.pathParameters['id']!);
            return Scaffold(appBar: AppBar(), body: const Text('Listing page'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      Provider<ListingRepository>(
        create: (_) => ListingRepository(
          ApiClient(
            client: MockClient((request) async {
              loads++;
              return jsonResponse({'listings': mine?.call() ?? _mine});
            }),
          ),
        ),
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, 1);
    return opened;
  }

  testWidgets('Listed and Unlisted chips filter the tab', (tester) async {
    await pumpTab(
      tester,
      mine: () => [
        ..._mine,
        {..._json('off'), 'status': 'paused'},
      ],
    );

    bool chosen(String label) => tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
        .selected;

    // Show comes first, with All chosen; Sort by sits underneath.
    expect(
      tester.getTopLeft(find.text('Show:')).dy,
      lessThan(tester.getTopLeft(find.text('Sort by:')).dy),
    );
    expect(find.byType(VerticalDivider), findsNothing);
    expect(chosen('All'), isTrue);
    expect(find.text('Item off'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Unlisted'));
    await tester.pumpAndSettle();
    expect(chosen('Unlisted'), isTrue);
    expect(chosen('All'), isFalse);
    expect(find.text('Item off'), findsOneWidget);
    expect(find.text('Item a'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Listed'));
    await tester.pumpAndSettle();
    expect(find.text('Item off'), findsNothing);
    expect(find.text('Item a'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.text('Item off'), findsOneWidget);
    expect(find.text('Item a'), findsOneWidget);
  });

  testWidgets('the rows stay when a filter finds nothing', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Unlisted'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing is unlisted right now.'), findsOneWidget);
    expect(find.text('Show:'), findsOneWidget);
    expect(find.text('Sort by:'), findsOneWidget);
  });

  testWidgets('sort chips reorder the Listings tab', (tester) async {
    await pumpTab(tester);
    double left(String title) => tester.getTopLeft(find.text(title)).dx;
    double top(String title) => tester.getTopLeft(find.text(title)).dy;

    expect(find.text('Sort by:'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(left('Item a'), lessThan(left('Item b')));

    await tester.tap(find.text('Pricing'));
    await tester.pumpAndSettle();
    expect(left('Item b'), lessThan(left('Item c')));
    expect(top('Item a'), greaterThan(top('Item b')));
  });

  testWidgets('an unlisted card can be tapped too', (tester) async {
    var taps = 0;
    final soldOut = Listing.fromJson(_json('d', stock: 0));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 250,
            child: ListingCard(listing: soldOut, onTap: () => taps++),
          ),
        ),
      ),
    );

    expect(find.text('Unlisted - No Stock'), findsOneWidget);
    await tester.tap(find.byType(ListingCard));
    expect(taps, 1);
  });

  Future<void> pumpCard(WidgetTester tester, {required bool relisted}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 250,
                child: ListingCard(
                  listing: Listing.fromJson(_json('e', stock: 3)),
                  onTap: () {},
                  relisted: relisted,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('a relisted card shows the Relisted ribbon', (tester) async {
    await pumpCard(tester, relisted: true);
    expect(find.byKey(const ValueKey('relisted-ribbon')), findsOneWidget);
    expect(find.text('Relisted'), findsOneWidget);
    expect(find.text('3 in stock'), findsOneWidget);
    expect(tester.getSize(find.byType(ListingCard)), const Size(200, 250));
  });

  testWidgets('other cards show no Relisted ribbon', (tester) async {
    await pumpCard(tester, relisted: false);
    expect(find.text('Relisted'), findsNothing);
  });

  testWidgets('relisted while turned off shows Relisted under Unlisted', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 250,
              child: ListingCard(
                listing: Listing.fromJson({..._json('p'), 'status': 'paused'}),
                onTap: () {},
                relisted: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Unlisted - Turned Off'), findsOneWidget);
    expect(find.text('Relisted'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Relisted')).dy,
      greaterThan(tester.getBottomLeft(find.text('Unlisted - Turned Off')).dy),
    );
    expect(
      find.ancestor(of: find.text('Relisted'), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('relisting from the listing page shows Relisted until the tab '
      'is left', (tester) async {
    final earlier = _now.subtract(const Duration(days: 1));
    var served = [
      for (final json in _mine)
        {...json, 'listedAt': earlier.toUtc().toIso8601String()},
    ];
    await pumpTab(tester, mine: () => served);

    await tester.tap(find.widgetWithText(ListingCard, 'Item c'));
    await tester.pumpAndSettle();
    served = [
      for (final json in served)
        json['_id'] == 'c'
            ? {...json, 'listedAt': _now.toUtc().toIso8601String()}
            : json,
    ];
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Relisted'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListingCard, 'Item c'),
        matching: find.text('Relisted'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ListingCard, 'Item a'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Relisted'), findsNothing);
  });

  Future<List<String>> pumpEnded(WidgetTester tester, Duration endsIn) async {
    final taps = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 250,
              child: ListingCard(
                listing: Listing.fromJson({
                  ..._json('e', stock: 3),
                  'pickupEnd': _now.add(endsIn).toUtc().toIso8601String(),
                }),
                onTap: () => taps.add('card'),
                onRelist: () => taps.add('relist'),
              ),
            ),
          ),
        ),
      ),
    );
    return taps;
  }

  testWidgets('an ended card shows Relist on its picture', (tester) async {
    final taps = await pumpEnded(tester, const Duration(hours: -1));

    final relist = find.byKey(const ValueKey('card-relist'));
    expect(relist, findsOneWidget);
    expect(find.text('Relist Now'), findsOneWidget);
    expect(find.byIcon(Icons.replay), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Unlisted - Pickup Ended'), findsOneWidget);
    expect(find.text('3 in stock'), findsOneWidget);
    expect(tester.getSize(find.byType(ListingCard)), const Size(200, 250));
    // It sits in the picture, above the text, at full colour.
    expect(
      tester.getCenter(find.text('Relist Now')).dy,
      lessThan(tester.getTopLeft(find.text('Item e')).dy),
    );
    expect(
      find.ancestor(
        of: find.text('Relist Now'),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(
      tester.widget<Text>(find.text('Relist Now')).style?.color,
      AppTheme.light.colorScheme.primary,
    );

    // The text area keeps its tap ripple.
    expect(
      find.ancestor(of: find.text('Item e'), matching: find.byType(InkWell)),
      findsOneWidget,
    );

    await tester.tap(find.text('Relist Now'));
    await tester.tap(find.text('Item e'));
    expect(taps, ['relist', 'card']);
  });

  testWidgets('cards still within pickup show no Relist', (tester) async {
    await pumpEnded(tester, const Duration(hours: 1));
    expect(find.byKey(const ValueKey('card-relist')), findsNothing);
  });

  testWidgets('tapping a card opens its listing page', (tester) async {
    final opened = await pumpTab(tester);

    await tester.tap(find.widgetWithText(ListingCard, 'Item c'));
    await tester.pumpAndSettle();
    expect(opened, ['c']);
    expect(find.text('Listing page'), findsOneWidget);
  });
}
