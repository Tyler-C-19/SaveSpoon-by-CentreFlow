import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/auth/presentation/providers/auth_provider.dart';
import 'package:savespoon/features/cart/data/cart_repository.dart';
import 'package:savespoon/features/cart/presentation/providers/cart_provider.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/data/recent_searches.dart';
import 'package:savespoon/features/listings/data/saved_filters.dart';
import 'package:savespoon/features/listings/domain/search_filters.dart';
import 'package:savespoon/features/listings/presentation/pages/search_page.dart';
import 'package:savespoon/features/listings/presentation/providers/listing_changes.dart';
import 'package:savespoon/features/map/data/position_source.dart';
import 'package:savespoon/features/map/domain/map_stall.dart';
import 'package:savespoon/features/map/presentation/pages/food_map_page.dart';
import 'package:savespoon/features/map/presentation/providers/user_location_provider.dart';
import 'package:savespoon/features/map/presentation/widgets/location_note.dart';
import 'package:savespoon/features/map/presentation/widgets/stall_marker.dart';
import 'package:savespoon/features/orders/data/order_repository.dart';
import 'package:savespoon/features/seller_profile/domain/geo_point.dart';

import 'helpers.dart';

// Android 14+ grows small text more than large text.
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

const _here = GeoPoint(1.5565, 103.641);

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Map<String, dynamic> _listing({
  String id = 'l1',
  String title = 'Nasi Lemak',
}) => {
  '_id': id,
  'title': title,
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': 10,
  'soldCount': 2,
  'pickupStart': _inHours(-1),
  'pickupEnd': _inHours(3),
  'allergens': const <String>[],
  'otherAllergens': const <String>[],
  'status': 'active',
  'stallName': 'Warung Pak Din',
  'pickupAddress': 'Cafeteria A, UTM Skudai',
  'location': [103.6385, 1.559],
};

Map<String, dynamic> _stall(
  String name,
  int count, {
  String id = 'l1',
  List<Map<String, dynamic>>? matches,
}) => {
  'stallName': name,
  'address': '$name address',
  'location': [103.6385, 1.559],
  'count': count,
  'listing': _listing(id: id),
  'matches': matches ?? [_listing(id: id)],
};

class _Server {
  List<Map<String, dynamic>> stalls = [
    _stall('Warung Pak Din', 3),
    _stall('Kafe Cendana', 1, id: 'l2'),
  ];
  bool failing = false;
  final List<Uri> sent = [];

  Future<http.Response> handle(http.Request request) async {
    sent.add(request.url);
    final path = request.url.path;
    if (path == '/api/favourites/ids') return jsonResponse({'listingIds': []});
    if (failing) return jsonResponse({'error': 'Server unavailable.'}, 503);
    if (path == '/api/listings/map') return jsonResponse({'stalls': stalls});
    if (path.endsWith('/vendor')) {
      return jsonResponse({
        'vendor': {'stallName': 'Warung Pak Din', 'address': 'Cafeteria A'},
        'otherListings': [_listing(), _listing(id: 'l3', title: 'Teh Tarik')],
      });
    }
    return jsonResponse({'listings': [], 'hasMore': false, 'otherStalls': []});
  }

  List<Uri> get mapRequests => [
    for (final url in sent)
      if (url.path == '/api/listings/map') url,
  ];
}

// Stands in for Google's map: one button per marker.
class _FakeMap {
  StallMapView? view;
  final List<MapMove> moves = [];
  bool _readySent = false;

  Widget build(BuildContext context, StallMapView view) {
    if (!_readySent) {
      _readySent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => view.onReady?.call());
    }
    if (this.view?.moves != view.moves) {
      view.moves.addListener(() {
        final move = view.moves.value;
        if (move != null) moves.add(move.$1);
      });
    }
    this.view = view;
    return ListView(
      padding: EdgeInsets.only(top: view.padding.top),
      children: [
        for (final stall in view.stalls)
          TextButton(
            key: ValueKey('marker-${stall.stallName}'),
            onPressed: () => view.onStallTap(stall),
            child: Text('${stall.stallName} (${stall.count})'),
          ),
      ],
    );
  }
}

Widget _providers(_Server server, UserLocationProvider location, Widget child) {
  final api = ApiClient(client: MockClient(server.handle));
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      Provider<ListingRepository>(create: (_) => ListingRepository(api)),
      Provider<OrderRepository>(create: (_) => OrderRepository(api)),
      ChangeNotifierProvider<ListingChanges>(create: (_) => ListingChanges()),
      ChangeNotifierProvider<UserLocationProvider>.value(value: location),
      favouritesProvider(server.handle),
      ChangeNotifierProvider<CartProvider>(
        create: (_) => CartProvider(CartRepository(api)),
      ),
    ],
    child: child,
  );
}

Future<_FakeMap> _pumpMap(
  WidgetTester tester,
  _Server server,
  FakePositionSource source, {
  String query = '',
  SearchFilters filters = SearchFilters.none,
  double width = 411,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final map = _FakeMap();
  await tester.pumpWidget(
    _providers(
      server,
      UserLocationProvider(source),
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: _AndroidText(scale)),
          child: child!,
        ),
        home: FoodMapPage(
          query: query,
          filters: filters,
          mapBuilder: map.build,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return map;
}

FakePositionSource _allowed({bool approximate = false}) => FakePositionSource(
  access: LocationAccess.allowed,
  position: _here,
  approximate: approximate,
);

Finder _key(String key) => find.byKey(ValueKey(key));

class _Recent implements RecentSearchStore {
  @override
  Future<List<String>> read(String accountId) async => [];

  @override
  Future<void> write(String accountId, List<String> searches) async {}
}

class _Filters implements SearchFilterStore {
  _Filters(this.saved);

  SearchFilters saved;

  @override
  Future<SearchFilters> read(String accountId) async => saved;

  @override
  Future<void> write(String accountId, SearchFilters filters) async =>
      saved = filters;
}

Future<UserLocationProvider> _pumpSearch(
  WidgetTester tester,
  _Server server,
  FakePositionSource source, {
  SearchFilters saved = SearchFilters.none,
  double width = 800,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final location = UserLocationProvider(source);
  final router = GoRouter(
    initialLocation: '/customer/search',
    routes: [
      GoRoute(
        path: '/customer/search',
        builder: (context, state) => Scaffold(
          body: SearchPage(store: _Recent(), filterStore: _Filters(saved)),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    _providers(
      server,
      location,
      MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: _AndroidText(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return location;
}

void main() {
  group('Food Map page', () {
    testWidgets(
      'never asks itself, shows one marker per stall and fits them at once',
      (tester) async {
        final server = _Server();
        final source = _allowed();
        final map = await _pumpMap(tester, server, source);

        expect(find.text(FoodMapPage.title), findsOneWidget);
        expect(find.text('Food Near You'), findsOneWidget);
        expect(
          map.view!.padding.top,
          greaterThan(0),
          reason: 'clear of the card',
        );
        expect(source.requests, 0, reason: 'Search asks before opening');
        expect(find.text('Warung Pak Din (3)'), findsOneWidget);
        expect(find.text('Kafe Cendana (1)'), findsOneWidget);
        expect(map.view!.here, _here);
        expect(map.moves, [MapMove.fitNow], reason: 'no camera jump');
        expect(server.mapRequests.single.query, isEmpty);

        await tester.tap(_key('my-location'));
        await tester.pump();
        expect(map.moves.last, MapMove.showMe);
      },
    );

    testWidgets('a marker opens the stall pane with all its items', (
      tester,
    ) async {
      final server = _Server();
      await _pumpMap(tester, server, _allowed());

      await tester.tap(_key('marker-Warung Pak Din'));
      await tester.pumpAndSettle();

      expect(find.text('On Sale at This Stall'), findsOneWidget);
      expect(find.text('Teh Tarik'), findsOneWidget);
      expect(
        server.sent.map((url) => url.toString()),
        contains(endsWith('/api/listings/l1/vendor?all=1')),
      );

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('On Sale at This Stall'), findsNothing);
      expect(find.text(FoodMapPage.title), findsOneWidget);
    });

    testWidgets('from a search, the pane shows what matched first', (
      tester,
    ) async {
      final server = _Server()
        ..stalls = [
          _stall(
            'Kafe Cendana',
            1,
            id: 'n1',
            matches: [_listing(id: 'n1', title: 'Nasi Goreng Kampung')],
          ),
        ];
      await _pumpMap(tester, server, _allowed(), query: 'nasi');

      await tester.tap(_key('marker-Kafe Cendana'));
      await tester.pumpAndSettle();

      final nasi = tester.getTopLeft(
        find.text('Nasi Goreng Kampung', skipOffstage: false),
      );
      final teh = tester.getTopLeft(
        find.text('Teh Tarik', skipOffstage: false),
      );
      expect(nasi.dx, lessThan(teh.dx), reason: 'the match comes first');
    });

    testWidgets('without a search, the pane keeps its usual order', (
      tester,
    ) async {
      final server = _Server()
        ..stalls = [
          _stall(
            'Kafe Cendana',
            1,
            id: 'n1',
            matches: [_listing(id: 'n1', title: 'Nasi Goreng Kampung')],
          ),
        ];
      await _pumpMap(tester, server, _allowed());

      await tester.tap(_key('marker-Kafe Cendana'));
      await tester.pumpAndSettle();

      expect(find.text('Nasi Goreng Kampung'), findsNothing);
      expect(find.text('Teh Tarik'), findsOneWidget);
    });

    testWidgets('the map has its own filter button, without Sort By', (
      tester,
    ) async {
      final server = _Server();
      await _pumpMap(tester, server, _allowed());

      await tester.tap(_key('map-filter-button'));
      await tester.pumpAndSettle();
      expect(find.text('Sort By'), findsNothing);

      await tester.tap(_key('filter-halal'));
      await tester.pumpAndSettle();
      await tester.tap(_key('filter-apply'));
      await tester.pumpAndSettle();

      expect(server.mapRequests.last.queryParameters, {'halal': '1'});
      expect(find.text('Best Matches'), findsOneWidget);
      expect(_key('active-filter-halal'), findsOneWidget);
    });

    testWidgets(
      'errors use the banner look, with a plug when the server is down',
      (tester) async {
        final server = _Server()..failing = true;
        await _pumpMap(tester, server, _allowed());

        expect(find.byType(MapBanner), findsOneWidget);
        expect(find.byIcon(Icons.power_off_outlined), findsOneWidget);
        expect(find.text('Try Again'), findsOneWidget);
      },
    );

    testWidgets('the map reaches the bottom of the screen', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPadding);
      final map = await _pumpMap(tester, _Server(), _allowed());

      expect(map.view!.padding.bottom, 48);
      final body = tester.getRect(find.byType(ListView).first);
      expect(body.bottom, 900, reason: 'no white bar at the bottom');
      expect(
        tester.getRect(_key('my-location')).bottom,
        lessThanOrEqualTo(900 - 48),
      );
    });

    testWidgets('stall details load in the background before a pin is tapped', (
      tester,
    ) async {
      final server = _Server();
      await _pumpMap(tester, server, _allowed());

      final vendorCalls = [
        for (final url in server.sent)
          if (url.path.endsWith('/vendor')) url.toString(),
      ];
      expect(vendorCalls, hasLength(2));
      expect(vendorCalls, everyElement(endsWith('?all=1')));

      await tester.tap(_key('marker-Warung Pak Din'));
      await tester.pump();
      expect(find.text('On Sale at This Stall'), findsOneWidget);
      expect(
        server.sent.where((url) => url.path.endsWith('/vendor')),
        hasLength(2),
        reason: 'opened from what was already loaded',
      );
    });

    testWidgets('the pane shows the distance once, not on its cards', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        _Server(),
        FakePositionSource(
          access: LocationAccess.allowed,
          afterRequest: LocationAccess.allowed,
          last: _here,
        ),
      );
      await tester.tap(_key('marker-Warung Pak Din'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('distance-line')), findsOneWidget);
      expect(find.text('390 m away'), findsOneWidget);
      expect(find.byKey(const ValueKey('distance-pill')), findsNothing);
    });

    testWidgets('searching on the map changes only the map', (tester) async {
      final server = _Server();
      await _pumpMap(tester, server, _allowed());

      await tester.enterText(_key('map-search-box'), 'nasi');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(server.mapRequests.last.queryParameters, {'q': 'nasi'});
      expect(find.text('Results for "nasi"'), findsOneWidget);

      await tester.tap(_key('map-search-clear'));
      await tester.pumpAndSettle();
      expect(server.mapRequests.last.query, isEmpty);
      expect(find.text('Food Near You'), findsOneWidget);
    });

    testWidgets('zoom buttons sit above My Location, the same size', (
      tester,
    ) async {
      final map = await _pumpMap(tester, _Server(), _allowed());

      final zoomIn = tester.getRect(_key('zoom-in'));
      final zoomOut = tester.getRect(_key('zoom-out'));
      final me = tester.getRect(_key('my-location'));
      expect(zoomIn.size, me.size);
      expect(zoomOut.size, me.size);
      expect(zoomIn.bottom, lessThanOrEqualTo(zoomOut.top));
      expect(zoomOut.bottom, lessThanOrEqualTo(me.top));
      expect(zoomIn.center.dx, moreOrLessEquals(me.center.dx));
      expect(me.center.dx, greaterThan(411 / 2), reason: 'on the right');
      await tester.tap(_key('zoom-in'));
      await tester.tap(_key('zoom-out'));
      await tester.pump();
      expect(map.moves.sublist(map.moves.length - 2), [
        MapMove.zoomIn,
        MapMove.zoomOut,
      ]);
    });

    testWidgets('Clear All stays in view with many filters', (tester) async {
      for (final width in [320.0, 411.0]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(const SizedBox());
          final server = _Server();
          await _pumpMap(
            tester,
            server,
            _allowed(),
            filters: const SearchFilters(
              categories: {'Rice', 'Noodles', 'Desserts'},
              halalOnly: true,
              maxPrice: 5,
              favouritesOnly: true,
              openNow: true,
            ),
            width: width,
            scale: scale,
          );
          final clear = tester.getRect(_key('active-filter-clear-all'));
          expect(
            clear.right,
            lessThanOrEqualTo(width),
            reason: 'w$width x$scale',
          );
          expect(clear.left, greaterThanOrEqualTo(0));

          await tester.tap(_key('active-filter-clear-all'));
          await tester.pumpAndSettle();
          expect(server.mapRequests.last.query, isEmpty);
        }
      }
    });

    testWidgets('emptying the search box resets the map without Search', (
      tester,
    ) async {
      final server = _Server();
      await _pumpMap(tester, server, _allowed(), query: 'nasi');
      expect(find.text('Results for "nasi"'), findsOneWidget);

      await tester.enterText(_key('map-search-box'), '');
      await tester.pumpAndSettle();

      expect(find.text('Food Near You'), findsOneWidget);
      expect(server.mapRequests.last.query, isEmpty);
    });

    testWidgets('without location, zoom buttons still show', (tester) async {
      await _pumpMap(tester, _Server(), FakePositionSource());
      expect(_key('zoom-in'), findsOneWidget);
      expect(_key('my-location'), findsNothing);
    });

    testWidgets('a white veil covers the map until its first view is drawn', (
      tester,
    ) async {
      await _pumpMap(tester, _Server(), _allowed());
      expect(_key('map-veil'), findsNothing, reason: 'faded out and removed');
    });

    testWidgets('the veil lifts by itself if the map never says it is ready', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(411, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _providers(
          _Server(),
          UserLocationProvider(_allowed()),
          MaterialApp(
            theme: AppTheme.light,
            home: FoodMapPage(mapBuilder: (context, view) => const SizedBox()),
          ),
        ),
      );
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(_key('map-veil')).opacity, 1);

      await tester.pump(FoodMapPage.revealAfter);
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(_key('map-veil')).opacity, 0);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_key('map-veil'), findsNothing);
    });

    testWidgets('empty, then error with Try Again', (tester) async {
      final server = _Server()..stalls = [];
      await _pumpMap(tester, server, _allowed());
      expect(find.text(FoodMapPage.emptyMessage), findsOneWidget);

      server.failing = true;
      await tester.pumpWidget(const SizedBox());
      await _pumpMap(tester, server, _allowed());
      expect(find.text('Server unavailable.'), findsOneWidget);

      server
        ..failing = false
        ..stalls = [_stall('Warung Pak Din', 3)];
      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(find.text('Warung Pak Din (3)'), findsOneWidget);
    });

    testWidgets(
      "Search's keyword and filters narrow the map, and chips remove them",
      (tester) async {
        final server = _Server()..stalls = [];
        await _pumpMap(
          tester,
          server,
          _allowed(),
          query: 'nasi',
          filters: const SearchFilters(halalOnly: true, maxPrice: 5),
        );

        expect(find.text('Results for "nasi"'), findsOneWidget);
        expect(find.text(FoodMapPage.noMatchMessage), findsOneWidget);
        expect(server.mapRequests.last.queryParameters, {
          'q': 'nasi',
          'halal': '1',
          'maxPrice': '5.00',
        });

        await tester.tap(
          find.descendant(
            of: _key('active-filter-halal'),
            matching: find.byIcon(Icons.close),
          ),
        );
        await tester.pumpAndSettle();
        expect(server.mapRequests.last.queryParameters, {
          'q': 'nasi',
          'maxPrice': '5.00',
        });
      },
    );

    testWidgets(
      'without permission the map still works, with a way to allow it',
      (tester) async {
        final server = _Server();
        final source = FakePositionSource(position: _here);
        final map = await _pumpMap(tester, server, source);

        expect(find.text('Warung Pak Din (3)'), findsOneWidget);
        expect(map.view!.here, isNull);
        expect(_key('my-location'), findsNothing);
        expect(find.text(LocationNote.denied), findsOneWidget);

        source.afterRequest = LocationAccess.allowed;
        await tester.tap(find.text('Allow Location'));
        await tester.pumpAndSettle();
        expect(map.view!.here, _here);
        expect(find.text(LocationNote.denied), findsNothing);
      },
    );

    testWidgets(
      'permanently denied opens Settings; location off opens location settings',
      (tester) async {
        final server = _Server();
        final denied = FakePositionSource(access: LocationAccess.deniedForever);
        await _pumpMap(tester, server, denied);
        expect(find.text(LocationNote.deniedForever), findsOneWidget);
        await tester.tap(find.text('Open Settings'));
        expect(denied.appSettingsOpened, 1);

        final off = FakePositionSource(access: LocationAccess.serviceOff);
        await tester.pumpWidget(const SizedBox());
        await _pumpMap(tester, server, off);
        expect(find.text(LocationNote.serviceOff), findsOneWidget);
        await tester.tap(find.text('Turn On Location'));
        expect(off.locationSettingsOpened, 1);
      },
    );

    testWidgets('approximate location says distances are approximate', (
      tester,
    ) async {
      await _pumpMap(tester, _Server(), _allowed(approximate: true));
      expect(find.text(LocationNote.approximate), findsOneWidget);
      expect(find.text('Allow Location'), findsNothing);
    });

    testWidgets('the top of the map never overflows', (tester) async {
      for (final width in [320.0, 360.0, 411.0]) {
        for (final scale in [1.0, 1.3, 1.5, 2.0]) {
          await tester.pumpWidget(const SizedBox());
          await _pumpMap(
            tester,
            _Server()..stalls = [],
            FakePositionSource(access: LocationAccess.deniedForever),
            query: 'nasi lemak ayam goreng berempah',
            filters: const SearchFilters(
              halalOnly: true,
              maxPrice: 5,
              favouritesOnly: true,
              openNow: true,
            ),
            width: width,
            scale: scale,
          );
          final error = tester.takeException();
          if (error != null) fail('width $width, text x$scale: $error');
          expect(
            tester.getSize(_key('map-card')).height,
            lessThanOrEqualTo(900 * FoodMapPage.maxCardShare + 0.01),
          );
        }
      }
    });
  });

  group('Search', () {
    testWidgets(
      'tapping the map icon asks for location first, then opens the map',
      (tester) async {
        final server = _Server();
        final source = FakePositionSource(
          afterRequest: LocationAccess.allowed,
          position: _here,
        );
        final location = await _pumpSearch(tester, server, source);

        await tester.tap(_key('search-map-button'));
        await tester.pumpAndSettle();

        expect(source.requests, 1);
        expect(location.access, LocationAccess.allowed);
        expect(find.byType(FoodMapPage), findsOneWidget);
        expect(
          server.mapRequests,
          hasLength(1),
          reason: 'the stalls loaded while asking are used, not loaded again',
        );
      },
    );

    testWidgets('the map button opens the map with the keyword and filters', (
      tester,
    ) async {
      final server = _Server()..stalls = [];
      await _pumpSearch(
        tester,
        server,
        _allowed(),
        saved: const SearchFilters(halalOnly: true),
      );

      await tester.enterText(_key('search-box'), 'nasi');
      await tester.pumpAndSettle();
      await tester.tap(_key('search-map-button'));
      await tester.pumpAndSettle();

      expect(find.byType(FoodMapPage), findsOneWidget);
      expect(server.mapRequests.last.queryParameters, {
        'q': 'nasi',
        'halal': '1',
      });
    });

    testWidgets('the search box fits the map button at every size', (
      tester,
    ) async {
      for (final width in [320.0, 360.0, 411.0]) {
        for (final scale in [1.0, 1.3, 1.5, 2.0]) {
          await tester.pumpWidget(const SizedBox());
          await _pumpSearch(
            tester,
            _Server(),
            FakePositionSource(),
            saved: const SearchFilters(halalOnly: true),
            width: width,
            scale: scale,
          );
          await tester.enterText(_key('search-box'), 'nasi lemak');
          await tester.pumpAndSettle();
          final error = tester.takeException();
          if (error != null) fail('width $width, text x$scale: $error');
          expect(
            tester.getRect(_key('search-map-button')).right,
            lessThanOrEqualTo(width),
          );
        }
      }
    });

    testWidgets('Nearest asks for location, then sends it rounded', (
      tester,
    ) async {
      final server = _Server();
      final source = FakePositionSource(
        afterRequest: LocationAccess.allowed,
        position: const GeoPoint(1.5565123, 103.6410456),
      );
      await _pumpSearch(tester, server, source);

      await tester.tap(_key('filter-button'));
      await tester.pumpAndSettle();
      await tester.tap(_key('sort-nearest'));
      await tester.pumpAndSettle();
      expect(source.requests, 1);
      await tester.tap(_key('filter-apply'));
      await tester.pumpAndSettle();

      final search = server.sent.lastWhere(
        (url) => url.path == '/api/listings/search',
      );
      expect(search.queryParameters['sort'], 'nearest');
      expect(search.queryParameters['lat'], '1.557');
      expect(search.queryParameters['lng'], '103.641');
    });

    testWidgets('Nearest stays unpicked when location is refused', (
      tester,
    ) async {
      final server = _Server();
      final source = FakePositionSource(access: LocationAccess.deniedForever);
      await _pumpSearch(tester, server, source);

      await tester.tap(_key('filter-button'));
      await tester.pumpAndSettle();
      await tester.tap(_key('sort-nearest'));
      await tester.pumpAndSettle();

      expect(find.text(LocationNote.deniedForever), findsOneWidget);
      expect(tester.widget<ChoiceChip>(_key('sort-nearest')).selected, isFalse);
      expect(
        tester.widget<FilledButton>(_key('filter-apply')).onPressed,
        isNull,
      );
    });
  });

  test('the pin label carries the distance when it is known', () {
    final stall = MapStall.fromJson(_stall('Warung Pak Din', 3))!;
    expect(stallDistance(stall, _here), '390 m');
    expect(stallDistance(stall, null), isNull);
  });

  testWidgets('a pin with a name draws its label under the tip', (
    tester,
  ) async {
    final icons = StallMarkerIcons(
      fill: AppColors.primary,
      onFill: Colors.white,
      labelText: Colors.black,
      labelFill: Colors.white,
    );
    final (plain, named) = (await tester.runAsync(
      () async => (
        await icons.icon(3, scale: 1, pixelRatio: 2),
        await icons.icon(
          3,
          name: 'Warung Nasi Campur Pak Din Yang Sangat Terkenal',
          distance: '390 m',
          scale: 1,
          pixelRatio: 2,
        ),
      ),
    ))!;
    expect(plain.anchor, StallMarkerIcons.anchor);
    expect(named.anchor.dx, 0.5);
    expect(named.anchor.dy, lessThan(plain.anchor.dy), reason: 'label below');
  });

  test('the pin is a teardrop whose tip marks the stall', () {
    final pin = StallMarkerIcons.pinPath(1);
    for (final inside in const [
      Offset(18, 1),
      Offset(1, 18),
      Offset(35, 18),
      Offset(18, 46),
    ]) {
      expect(pin.contains(inside), isTrue, reason: '$inside');
    }
    for (final outside in const [
      Offset(-2, 18),
      Offset(38, 18),
      Offset(18, -2),
      Offset(3, 44),
      Offset(33, 44),
      Offset(18, 49),
    ]) {
      expect(pin.contains(outside), isFalse, reason: '$outside');
    }
    expect(StallMarkerIcons.anchor.dx, 0.5);
    expect(StallMarkerIcons.anchor.dy, greaterThan(0.9));
    expect(StallMarkerIcons.countLabel(120), '99+');
  });

  test('a stall without a pin is skipped', () {
    expect(
      MapStall.fromJson({'stallName': 'X', 'listing': _listing()}),
      isNull,
    );
  });
}
