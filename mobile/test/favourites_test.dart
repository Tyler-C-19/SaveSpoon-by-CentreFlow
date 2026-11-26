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
import 'package:savespoon/features/cart/data/cart_repository.dart';
import 'package:savespoon/features/cart/presentation/providers/cart_provider.dart';
import 'package:savespoon/features/listings/data/favourites_repository.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/pages/customer_home_page.dart';
import 'package:savespoon/features/listings/presentation/pages/food_details_page.dart';
import 'package:savespoon/features/orders/data/order_repository.dart';
import 'package:savespoon/features/listings/presentation/providers/favourites_provider.dart';
import 'package:savespoon/features/listings/presentation/providers/listing_changes.dart';
import 'package:savespoon/features/listings/presentation/widgets/favourite_button.dart';
import 'package:savespoon/features/listings/presentation/widgets/favourites_strip.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_card.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_image.dart';
import 'package:savespoon/features/listings/presentation/widgets/quick_add_button.dart';
import 'package:savespoon/features/listings/presentation/widgets/search_result_row.dart';

import 'helpers.dart';

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Map<String, dynamic> _listing({
  String id = 'l1',
  String title = 'Nasi Lemak',
  String stall = 'Warung Pak Din',
}) => {
  '_id': id,
  'title': title,
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': 10,
  'pickupStart': _inHours(-1),
  'pickupEnd': _inHours(3),
  'allergens': const ['egg', 'milk'],
  'otherAllergens': const <String>[],
  'status': 'active',
  'stallName': stall,
  'pickupAddress': 'Arked Meranti, UTM Skudai',
};

class _Server {
  List<Map<String, dynamic>> listings = [_listing()];
  List<Map<String, dynamic>> favourites = [];
  List<String> favouriteIds = [];
  bool favouritesHasMore = false;
  List<Map<String, dynamic>> runningOut = [];
  // Holds the Favourites answer back, like a slower request.
  Completer<void>? favouritesWait;
  int favouriteLoads = 0;
  bool failSaves = false;
  http.Response? cartAnswer;
  final List<String> calls = [];
  final List<Map<String, dynamic>> cartBodies = [];

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (path == '/api/listings/favourites') {
      favouriteLoads++;
      await favouritesWait?.future;
      return jsonResponse({
        'listings': favourites,
        'hasMore': favouritesHasMore,
      });
    }
    if (path == '/api/favourites/ids') {
      return jsonResponse({'listingIds': favouriteIds});
    }
    if (path.startsWith('/api/favourites/')) {
      if (failSaves) return jsonResponse({'error': 'Server is down'}, 500);
      return jsonResponse({'favourite': request.method == 'PUT'});
    }
    if (path == '/api/cart/items') {
      cartBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return cartAnswer ??
          jsonResponse({
            'cart': {'items': [], 'total': 0, 'warnings': []},
            'message': 'Added 1 x Nasi Lemak to your cart.',
          });
    }
    if (path == '/api/listings/l1') {
      return jsonResponse({'listing': _listing()});
    }
    if (path.endsWith('/vendor')) {
      return jsonResponse({'error': 'Not used here'}, 404);
    }
    if (path == '/api/listings/running-out') {
      return jsonResponse({'listings': runningOut});
    }
    if (path == '/api/orders/again') {
      return jsonResponse({'listings': []});
    }
    return jsonResponse({'listings': listings, 'hasMore': false});
  }
}

Future<void> _pumpHome(
  WidgetTester tester,
  _Server server, {
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = ApiClient(client: MockClient(server.handle));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: CustomerHomePage(name: 'Aina')),
      ),
      GoRoute(
        path: '/customer/food/:id',
        builder: (context, state) =>
            Scaffold(body: Text('Details ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/customer/cart',
        builder: (context, state) => const Scaffold(body: Text('Cart tab')),
      ),
      GoRoute(
        path: '/customer/search',
        builder: (context, state) => const Scaffold(body: Text('Search tab')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ListingRepository>(create: (_) => ListingRepository(api)),
        Provider<OrderRepository>(create: (_) => OrderRepository(api)),
        ChangeNotifierProvider<ListingChanges>(create: (_) => ListingChanges()),
        ChangeNotifierProvider<FavouritesProvider>(
          create: (_) => FavouritesProvider(FavouritesRepository(api)),
        ),
        ChangeNotifierProvider<CartProvider>(
          create: (_) => CartProvider(CartRepository(api)),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder _heart(String id) => find.byKey(ValueKey('favourite-$id'));

Finder _inStrip(Finder finder) =>
    find.descendant(of: find.byType(FavouritesStrip), matching: finder);

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

const _widths = [320.0, 360.0, 411.0];
const _textScales = [1.0, 1.3, 1.5, 2.0];

Future<void> _expectNoOverflow(
  WidgetTester tester,
  Widget Function(double width) build, {
  void Function(double width, double scale)? check,
}) async {
  for (final width in _widths) {
    for (final scale in _textScales) {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ChangeNotifierProvider<FavouritesProvider>(
          create: (_) => FavouritesProvider(
            FavouritesRepository(
              ApiClient(
                client: MockClient(
                  (_) async => jsonResponse({'listingIds': []}),
                ),
              ),
            ),
          ),
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: _AndroidText(scale)),
              child: child!,
            ),
            home: Scaffold(body: build(width)),
          ),
        ),
      );
      final error = tester.takeException();
      if (error != null) fail('width $width, text x$scale: $error');
      check?.call(width, scale);
    }
  }
  tester.view.reset();
}

const _longName =
    'Extra Spicy Nasi Goreng Kampung with Fried Chicken and Sambal Petai';
const _longStall = 'Warung Makan Pak Din Selera Kampung Tradisional';

void main() {
  test('the failure message names Favourites, or gives the limit', () {
    expect(
      favouriteFailure(const ApiException('Server is down', statusCode: 500)),
      "Couldn't update your Favourites. Please try again.",
    );
    expect(
      favouriteFailure(
        const ApiException(
          'You can save up to 200 Favourites.',
          statusCode: 409,
          code: 'FAVOURITES_FULL',
        ),
      ),
      'You can save up to 200 Favourites.',
    );
  });

  testWidgets('a heart changes at once and never opens the food', (
    tester,
  ) async {
    final server = _Server();
    await _pumpHome(tester, server);

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(_heart('l1'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.favorite), findsWidgets);
    expect(find.text('Details l1'), findsNothing);
    expect(server.calls, contains('PUT /api/favourites/l1'));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.favorite).first).color,
      AppTheme.light.colorScheme.error,
    );
  });

  testWidgets('a failed heart goes back and says so', (tester) async {
    final server = _Server()..failSaves = true;
    await _pumpHome(tester, server);

    await tester.tap(_heart('l1'));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't update your Favourites. Please try again."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('a long-press on the heart only shows its name', (tester) async {
    final server = _Server();
    await _pumpHome(tester, server);

    await tester.longPress(_heart('l1'));
    await tester.pumpAndSettle();

    expect(find.text('Add to Favourites'), findsOneWidget);
    expect(server.calls.where((call) => call.endsWith('/vendor')), isEmpty);
    expect(find.text('Details l1'), findsNothing);
  });

  testWidgets('quick add puts one in the cart and offers View Cart', (
    tester,
  ) async {
    final server = _Server();
    await _pumpHome(tester, server);

    await tester.tap(find.byKey(const ValueKey('quick-add-l1')));
    await tester.pumpAndSettle();

    expect(server.cartBodies.single, {'listingId': 'l1', 'quantity': 1});
    expect(find.text('Added 1 x Nasi Lemak to your cart.'), findsOneWidget);
    expect(find.text('Details l1'), findsNothing);

    await tester.tap(find.text('View Cart'));
    await tester.pumpAndSettle();
    expect(find.text('Cart tab'), findsOneWidget);
  });

  testWidgets('quick add shows the cart message when it fails', (tester) async {
    final server = _Server()
      ..cartAnswer = jsonResponse({
        'code': 'SOLD_OUT',
        'error': 'This item has just sold out.',
      }, 409);
    await _pumpHome(tester, server);

    await tester.tap(find.byKey(const ValueKey('quick-add-l1')));
    await tester.pumpAndSettle();

    expect(find.text('This item has just sold out.'), findsOneWidget);
    expect(find.text('View Cart'), findsNothing);
  });

  testWidgets(
    'Your Favourites shows in the order received and hides when empty',
    (tester) async {
      final server = _Server()
        ..favourites = [
          _listing(id: 'b', title: 'Teh Tarik'),
          _listing(id: 'a', title: 'Kuih Box'),
        ]
        ..favouriteIds = ['b', 'a'];
      await _pumpHome(tester, server);

      expect(find.text('Your Favourites'), findsOneWidget);
      expect(
        tester.getTopLeft(_inStrip(find.text('Teh Tarik'))).dx,
        lessThan(tester.getTopLeft(_inStrip(find.text('Kuih Box'))).dx),
      );
      expect(
        tester.getTopLeft(find.text('Your Favourites')).dy,
        lessThan(tester.getTopLeft(find.text("What's New")).dy),
      );

      await tester
          .element(find.byType(FavouritesStrip))
          .read<FavouritesProvider>()
          .ensureLoaded('u1');
      await tester.pumpAndSettle();
      final loads = server.favouriteLoads;
      server.favourites = [];
      await tester.tap(_inStrip(_heart('b')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(server.calls, contains('DELETE /api/favourites/b'));
      expect(server.favouriteLoads, loads + 1);
      expect(find.text('Your Favourites'), findsNothing);
    },
  );

  testWidgets('no Favourites means no strip', (tester) async {
    await _pumpHome(tester, _Server());
    expect(find.text('Your Favourites'), findsNothing);
  });

  testWidgets('pull to refresh reloads the Favourites strip', (tester) async {
    final server = _Server();
    await _pumpHome(tester, server);
    final loads = server.favouriteLoads;

    server.favourites = [_listing(id: 'c', title: 'Roti Jala')];
    await tester.fling(find.text("What's New"), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(server.favouriteLoads, greaterThan(loads));
    expect(find.text('Your Favourites'), findsOneWidget);
  });

  testWidgets(
    'Home cards with buttons never overflow, with the buttons in a row under the text',
    (tester) async {
      final listing = Listing.fromJson(
        _listing(title: _longName, stall: _longStall),
      );
      await _expectNoOverflow(
        tester,
        (width) => Center(
          child: SizedBox(
            width: (width - AppSpacing.md * 2 - AppSpacing.sm) / 2,
            child: Builder(
              builder: (context) => SizedBox(
                height: ListingCard.heightWithActions(context),
                child: ListingCard(
                  listing: listing,
                  showBadges: true,
                  onTap: () {},
                  actions: ListingActions(listing: listing),
                  actionsWidth: ListingActions.widthOf(context),
                ),
              ),
            ),
          ),
        ),
        check: (width, scale) {
          final reason = 'width $width, text x$scale';
          final photo = tester.getRect(find.byType(ListingImage));
          final heart = tester.getRect(_heart('l1'));
          final cart = tester.getRect(
            find.byKey(const ValueKey('quick-add-l1')),
          );
          final card = tester.getRect(find.byType(ListingCard));
          final price = tester.getRect(find.text('RM 4.50'));
          final allergens = find.textContaining('Allergens:');
          final save = tester.getRect(find.textContaining('Save'));
          if (scale == 1) {
            expect(card.height, ListingCard.browseHeight, reason: reason);
          }
          expect(heart.top, greaterThanOrEqualTo(photo.bottom), reason: reason);
          expect(heart.top, greaterThanOrEqualTo(price.bottom), reason: reason);
          expect(
            heart.top,
            greaterThanOrEqualTo(tester.getRect(allergens).bottom - 0.01),
            reason: reason,
          );
          expect(heart.top, cart.top, reason: 'side by side, $reason');
          expect(heart.right, lessThanOrEqualTo(cart.left + 0.01));
          expect(cart.right, lessThanOrEqualTo(card.right));
          expect(cart.bottom, lessThanOrEqualTo(card.bottom));
          expect(
            save.bottom <= photo.bottom,
            isTrue,
            reason: 'Save stays on the photo, $reason',
          );
          // The allergens line keeps the card's full width.
          expect(
            tester
                .getSize(
                  find
                      .ancestor(of: allergens, matching: find.byType(Row))
                      .first,
                )
                .width,
            moreOrLessEquals(card.width - AppSpacing.sm * 2, epsilon: 0.5),
            reason: reason,
          );
        },
      );
    },
  );

  testWidgets('Search rows with buttons never overflow', (tester) async {
    final listing = Listing.fromJson(
      _listing(title: _longName, stall: _longStall),
    );
    await _expectNoOverflow(
      tester,
      (width) => Center(
        child: SizedBox(
          width: width - AppSpacing.md * 2,
          child: SearchResultRow(
            listing: listing,
            onTap: () {},
            actions: ListingActions(listing: listing),
          ),
        ),
      ),
      check: (width, scale) {
        final reason = 'width $width, text x$scale';
        final row = tester.getRect(find.byType(SearchResultRow));
        final heart = tester.getRect(_heart('l1'));
        final cart = tester.getRect(find.byKey(const ValueKey('quick-add-l1')));
        final address = tester.getRect(find.text('Arked Meranti, UTM Skudai'));
        expect(heart.top, cart.top, reason: 'side by side, $reason');
        expect(cart.bottom, lessThanOrEqualTo(row.bottom), reason: reason);
        expect(cart.right, lessThanOrEqualTo(row.right), reason: reason);
        // Beside the lines when there's room, otherwise under them.
        expect(
          address.right <= heart.left || heart.top >= address.bottom,
          isTrue,
          reason: reason,
        );
        expect(cart.center.dx, greaterThan(row.center.dx), reason: reason);
      },
    );
  });

  testWidgets('Food Details has a heart in the top bar', (tester) async {
    final server = _Server();
    final api = ApiClient(client: MockClient(server.handle));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ListingRepository>(create: (_) => ListingRepository(api)),
          Provider<OrderRepository>(create: (_) => OrderRepository(api)),
          ChangeNotifierProvider<FavouritesProvider>(
            create: (_) => FavouritesProvider(FavouritesRepository(api)),
          ),
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

    final heart = find.descendant(
      of: find.byType(AppBar),
      matching: _heart('l1'),
    );
    expect(heart, findsOneWidget);
    await tester.tap(heart);
    await tester.pumpAndSettle();

    expect(server.calls, contains('PUT /api/favourites/l1'));
    expect(find.byTooltip('Remove from Favourites'), findsOneWidget);
  });

  testWidgets('icons grow as much as the text, but never shrink', (
    tester,
  ) async {
    final listing = Listing.fromJson(_listing());
    for (final (scale, expected) in [
      (0.85, 32.0),
      (1.0, 32.0),
      (1.3, 32 * 1.3),
      (2.0, 64.0),
    ]) {
      await tester.pumpWidget(
        ChangeNotifierProvider<FavouritesProvider>(
          create: (_) => FavouritesProvider(
            FavouritesRepository(
              ApiClient(
                client: MockClient(
                  (_) async => jsonResponse({'listingIds': []}),
                ),
              ),
            ),
          ),
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: ListingActions(listing: listing)),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(_heart('l1')).width,
        moreOrLessEquals(expected, epsilon: 0.5),
        reason: 'text x$scale',
      );
    }
  });

  testWidgets('hearts load again on the next refresh after a failure', (
    tester,
  ) async {
    final server = _Server()..favouriteIds = ['l1'];
    var failIds = true;
    final api = ApiClient(
      client: MockClient((request) async {
        if (request.url.path == '/api/favourites/ids' && failIds) {
          return jsonResponse({'error': 'Server is down'}, 500);
        }
        return server.handle(request);
      }),
    );
    final favourites = FavouritesProvider(FavouritesRepository(api));
    await favourites.ensureLoaded('u1');
    expect(favourites.isFavourite('l1'), isFalse);

    failIds = false;
    await favourites.ensureLoaded('u1');
    expect(favourites.isFavourite('l1'), isTrue);
  });

  testWidgets('the cart message with View Cart goes away by itself', (
    tester,
  ) async {
    await _pumpHome(tester, _Server());

    await tester.tap(find.byKey(const ValueKey('quick-add-l1')));
    await tester.pumpAndSettle();
    expect(find.text('Added 1 x Nasi Lemak to your cart.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Added 1 x Nasi Lemak to your cart.'), findsNothing);
  });

  testWidgets('View All shows only with more than 6, and opens Search', (
    tester,
  ) async {
    final server = _Server()
      ..favourites = [_listing(id: 'b', title: 'Teh Tarik')];
    await _pumpHome(tester, server);
    expect(find.byKey(const ValueKey('favourites-view-all')), findsNothing);

    server.favouritesHasMore = true;
    await tester.fling(find.text("What's New"), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('View All'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('favourites-view-all')));
    await tester.pumpAndSettle();

    expect(find.text('Search tab'), findsOneWidget);
  });

  testWidgets('Your Favourites opens and closes smoothly', (tester) async {
    final server = _Server()
      ..favourites = [_listing(id: 'b', title: 'Teh Tarik')]
      ..favouriteIds = ['b'];
    await _pumpHome(tester, server);
    await tester
        .element(find.byType(FavouritesStrip))
        .read<FavouritesProvider>()
        .ensureLoaded('u1');
    await tester.pumpAndSettle();
    final open = tester.getSize(find.byType(FavouritesStrip)).height;

    server.favourites = [];
    await tester.tap(_inStrip(_heart('b')));
    final heights = <double>[];
    for (var step = 0; step < 30; step++) {
      await tester.pump(const Duration(milliseconds: 50));
      heights.add(
        tester
            .getSize(find.byType(FavouritesStrip, skipOffstage: false))
            .height,
      );
    }
    // Some frames land between open and closed, rather than jumping.
    expect(heights.where((h) => h > 0 && h < open), isNotEmpty);

    await tester.pumpAndSettle();
    expect(heights.last, 0);
    expect(find.text('Your Favourites'), findsNothing);
  });

  testWidgets(
    'on the first load Your Favourites shows at once, like the rest',
    (tester) async {
      final server = _Server()
        ..favourites = [_listing(id: 'b', title: 'Teh Tarik')];
      await _pumpHome(tester, server, settle: false);

      final heights = <double>[];
      for (var step = 0; step < 30; step++) {
        await tester.pump(const Duration(milliseconds: 16));
        heights.add(
          tester
              .getSize(find.byType(FavouritesStrip, skipOffstage: false))
              .height,
        );
      }
      final open = heights.last;
      expect(open, greaterThan(0));
      expect(heights.where((h) => h > 0 && h < open), isEmpty);
    },
  );

  testWidgets(
    'Your Favourites photos are the same height as Running Out Soon',
    (tester) async {
      final server = _Server()
        ..favourites = [_listing(id: 'b', title: 'Teh Tarik')]
        ..runningOut = [_listing(id: 'c', title: 'Kuih Lapis')];
      await _pumpHome(tester, server);

      double photoOf(String title) => tester
          .getSize(
            find.descendant(
              of: find.ancestor(
                of: find.text(title).first,
                matching: find.byType(ListingCard),
              ),
              matching: find.byType(ListingImage),
            ),
          )
          .height;
      expect(find.text('Running Out Soon'), findsOneWidget);
      expect(photoOf('Teh Tarik'), photoOf('Kuih Lapis'));
    },
  );

  testWidgets('Home fades in once its first load is back', (tester) async {
    await _pumpHome(tester, _Server(), settle: false);
    FadeTransition fade() => tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(CustomerHomePage),
            matching: find.byType(FadeTransition),
          )
          .first,
    );

    final values = <double>[];
    for (var step = 0; step < 50; step++) {
      await tester.pump(const Duration(milliseconds: 16));
      values.add(fade().opacity.value);
    }
    expect(values.first, lessThan(1));
    expect(values.where((v) => v > 0 && v < 1), isNotEmpty);
    expect(values.last, 1);
  });

  testWidgets('Home waits for a slower Your Favourites, then shows it all', (
    tester,
  ) async {
    final server = _Server()
      ..favourites = [_listing(id: 'b', title: 'Teh Tarik')]
      ..favouritesWait = Completer<void>();
    await _pumpHome(tester, server, settle: false);
    FadeTransition fade() => tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(CustomerHomePage),
            matching: find.byType(FadeTransition),
          )
          .first,
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(fade().opacity.value, 0);

    server.favouritesWait!.complete();
    await tester.pumpAndSettle();
    expect(fade().opacity.value, 1);
    expect(find.text('Your Favourites'), findsOneWidget);
    expect(server.favouriteLoads, 1);
  });
}
