import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/constants/api_config.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/core/utils/external_links.dart';
import 'package:savespoon/features/cart/data/cart_repository.dart';
import 'package:savespoon/features/cart/domain/cart.dart';
import 'package:savespoon/features/cart/presentation/pages/cart_page.dart';
import 'package:savespoon/features/cart/presentation/providers/cart_provider.dart';
import 'package:savespoon/features/cart/presentation/widgets/cart_stall_heading.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/pages/food_details_page.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_card.dart';
import 'package:savespoon/features/listings/presentation/widgets/search_result_row.dart';
import 'package:savespoon/features/orders/data/order_repository.dart';
import 'package:savespoon/features/profile/presentation/widgets/profile_avatar.dart';
import 'package:savespoon/features/seller_profile/domain/vendor_info.dart';
import 'package:savespoon/features/seller_profile/presentation/widgets/pickup_info_row.dart';
import 'package:savespoon/features/seller_profile/presentation/widgets/text_with_action.dart';
import 'package:savespoon/features/seller_profile/presentation/widgets/vendor_details_card.dart';
import 'package:savespoon/features/seller_profile/presentation/widgets/vendor_pane.dart';

import 'helpers.dart';

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

// Like Android 14+: small text grows by [top], and the growth fades out by
// 100 sp, so a fixed "140 sp" box barely grows while the text in it does.
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

Map<String, dynamic> _listing({
  String id = 'l1',
  String title = 'Nasi Lemak',
  String stall = 'Warung Pak Din',
  int stock = 3,
  Map<String, dynamic> extra = const {},
}) => {
  '_id': id,
  'title': title,
  'description': 'With sambal',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': stock,
  'soldCount': 0,
  'pickupStart': _inHours(1),
  'pickupEnd': _inHours(3),
  'allergens': const ['egg'],
  'otherAllergens': const <String>[],
  'status': 'active',
  'stallName': stall,
  ...extra,
};

Map<String, dynamic> _details({
  String stall = 'Warung Pak Din',
  String address = 'Cafeteria A, UTM Skudai',
  String? phone = '012-345 6781',
  List<num>? location = const [103.6385, 1.559],
  String? placeId = 'place-1',
}) => _listing(
  stall: stall,
  extra: {
    'pickupAddress': address,
    'vendorPhone': ?phone,
    'pickupLocation': ?location,
    'pickupPlaceId': ?placeId,
  },
);

Map<String, dynamic> _vendor({
  String stall = 'Warung Pak Din',
  String? description = 'Home-style rice dishes',
  String? address = 'Cafeteria A, UTM Skudai',
  String? phone = '012-345 6781',
  String? photoUrl,
  List<num>? location = const [103.6385, 1.559],
  String? placeId = 'place-1',
  List<Map<String, dynamic>> others = const [],
}) => {
  'vendor': {
    'stallName': stall,
    'description': ?description,
    'address': ?address,
    'phone': ?phone,
    'photoUrl': ?photoUrl,
    'location': ?location,
    'placeId': ?placeId,
  },
  'otherListings': others,
};

final _cafeteriaA = directionsUri(
  lat: 1.559,
  lng: 103.6385,
  placeId: 'place-1',
  address: 'Cafeteria A, UTM Skudai',
);

class _Links {
  final List<Uri> opened = [];
  bool works = true;

  void install() {
    final previous = ExternalLinks.opener;
    ExternalLinks.opener = (uri) async {
      opened.add(uri);
      return works;
    };
    addTearDown(() => ExternalLinks.opener = previous);
  }
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

class _Server {
  _Server(this.respond);

  final FutureOr<http.Response> Function(http.Request request) respond;
  final List<String> paths = [];

  ApiClient get api => ApiClient(
    client: MockClient((request) async {
      paths.add(request.url.path);
      return respond(request);
    }),
  );

  int get vendorCalls => paths.where((path) => path.endsWith('/vendor')).length;
}

Widget _textScaled(Widget child, double scale) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: _AndroidText(scale)),
    child: child,
  ),
);

Widget _app(
  ListingRepository repository,
  ApiClient api,
  Widget home, {
  double textScale = 1,
}) => MultiProvider(
  providers: [
    Provider<ListingRepository>.value(value: repository),
    Provider<OrderRepository>(create: (_) => OrderRepository(api)),
    favouritesProvider((_) async => jsonResponse({'listingIds': []})),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => _textScaled(child!, textScale),
    home: home,
  ),
);

class _PaneHost {
  _PaneHost(this.server, this.repository);

  final _Server server;
  final ListingRepository repository;
  final List<Listing> openedListings = [];
}

Future<_PaneHost> _openPane(
  WidgetTester tester,
  FutureOr<http.Response> Function(http.Request request) respond, {
  Map<String, dynamic>? listing,
  Size size = const Size(800, 1600),
  double textScale = 1,
  bool settle = true,
  ListingRepository? repository,
}) async {
  _setSize(tester, size);
  final server = _Server(respond);
  final api = server.api;
  final host = _PaneHost(server, repository ?? ListingRepository(api));
  await tester.pumpWidget(
    _app(
      host.repository,
      api,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showVendorPane(
                context,
                listing: Listing.fromJson(listing ?? _listing()),
                onOpenListing: (other) async => host.openedListings.add(other),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      textScale: textScale,
    ),
  );
  await tester.tap(find.text('open'));
  if (settle) await tester.pumpAndSettle();
  return host;
}

Future<_Server> _openDetails(
  WidgetTester tester, {
  Map<String, dynamic>? listing,
  Map<String, dynamic>? vendor,
  Size size = const Size(800, 1600),
  double textScale = 1,
}) async {
  _setSize(tester, size);
  final server = _Server((request) {
    if (request.url.path.endsWith('/vendor')) {
      return jsonResponse(vendor ?? _vendor());
    }
    return jsonResponse({'listing': listing ?? _details()});
  });
  final api = server.api;
  await tester.pumpWidget(
    _app(
      ListingRepository(api),
      api,
      FoodDetailsPage(
        listingId: 'l1',
        onAddToCart: (context, id, quantity) async => 'Added',
        onOrdered: (context, orders) {},
      ),
      textScale: textScale,
    ),
  );
  await tester.pumpAndSettle();
  return server;
}

const _longStall =
    'Warung Makanan Tradisional Pak Din dan Keluarga Besar Kampung Baru';
const _longAddress =
    'Lot 12, Kafeteria Kolej Tun Dr Ismail, Jalan Universiti, Universiti '
    'Teknologi Malaysia, 81310 Skudai, Johor Darul Takzim';
const _longTitle = 'Nasi Lemak Ayam Goreng Berempah Special Extra Sambal Petai';

const _widths = [320.0, 411.0, 700.0];
const _scales = [1.0, 1.3, 1.5, 1.8, 2.0];
// Whole pages only at sizes their older rows already fit (see SVS-27); the
// SVS-15 parts are checked at every size on their own.
const _pageSizes = [(320.0, 1.0), (411.0, 1.0), (700.0, 1.0)];

Future<void> _pumpAlone(
  WidgetTester tester,
  Widget child, {
  required double width,
  required double scale,
}) async {
  _setSize(tester, Size(width, 1600));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => _textScaled(child!, scale),
      home: Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [child]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('links', () {
    test('a Google place goes by its address and place ID', () {
      expect(_cafeteriaA.host, 'www.google.com');
      expect(_cafeteriaA.path, '/maps/dir/');
      expect(_cafeteriaA.queryParameters, {
        'api': '1',
        'destination': 'Cafeteria A, UTM Skudai',
        'destination_place_id': 'place-1',
      });
    });

    test('a hand-placed pin keeps its exact coordinates', () {
      final uri = directionsUri(
        lat: 1.559,
        lng: 103.6385,
        address: 'Cafeteria A, UTM Skudai',
      );
      expect(uri.queryParameters, {
        'api': '1',
        'destination': '1.559,103.6385',
      });
    });

    test('the dialer gets the number without spaces or dashes', () {
      expect(phoneUri('012-345 6781').toString(), 'tel:0123456781');
      expect(phoneUri('+60 12-345 6781').toString(), 'tel:+60123456781');
    });
  });

  group('vendor data', () {
    test('reads the pin as [lng, lat] and the other listings', () {
      final info = VendorInfo.fromJson(
        _vendor(
          others: [_listing(id: 'l2', title: 'Mee Goreng')],
        ),
      );
      expect(info.location?.lat, 1.559);
      expect(info.location?.lng, 103.6385);
      expect(info.placeId, 'place-1');
      expect(info.otherListings.single.title, 'Mee Goreng');
    });

    test('missing values stay empty', () {
      final info = VendorInfo.fromJson(
        _vendor(description: null, phone: null, location: null, placeId: null),
      );
      expect(info.description, isNull);
      expect(info.phone, isNull);
      expect(info.location, isNull);
      expect(info.otherListings, isEmpty);
      expect(geoPointFrom('nope'), isNull);
      expect(geoPointFrom([1]), isNull);
      expect(geoPointFrom(['a', 'b']), isNull);
    });

    test('details and cart items read the pickup pin', () {
      final listing = Listing.fromJson(_details());
      expect(listing.pickupLocation?.lat, 1.559);
      expect(listing.pickupPlaceId, 'place-1');
      expect(listing.vendorPhone, '012-345 6781');

      final item = CartItem.fromJson({
        ..._cartItem(),
        'pickupLocation': [103.6385, 1.559],
        'pickupPlaceId': 'place-1',
      });
      expect(item.pickupLocation?.lng, 103.6385);
      expect(item.pickupPlaceId, 'place-1');
      expect(CartItem.fromJson(_cartItem()).pickupLocation, isNull);
    });

    test(
      'vendor info loads once, is kept briefly and shares one request',
      () async {
        final server = _Server((_) => jsonResponse(_vendor()));
        final repository = ListingRepository(server.api);

        expect(repository.cachedVendorInfo('l1'), isNull);
        repository.prefetchVendorInfo('l1');
        final info = await repository.fetchVendorInfo('l1');
        expect(server.vendorCalls, 1);
        expect(info.stallName, 'Warung Pak Din');
        expect(repository.cachedVendorInfo('l1'), isNotNull);
        expect(repository.isVendorInfoFresh('l1'), isTrue);

        repository.prefetchVendorInfo('l1');
        expect(server.vendorCalls, 1);
      },
    );

    test('a failed prefetch leaves nothing behind', () async {
      final server = _Server((_) => jsonResponse({'error': 'down'}, 500));
      final repository = ListingRepository(server.api);
      repository.prefetchVendorInfo('l1');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(repository.cachedVendorInfo('l1'), isNull);
      await expectLater(
        repository.fetchVendorInfo('l1'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('vendor pane', () {
    testWidgets('shows what the listing knows straight away', (tester) async {
      final reply = Completer<http.Response>();
      await _openPane(
        tester,
        (_) => reply.future,
        listing: _details(),
        settle: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Vendor Details'), findsOneWidget);
      expect(find.text('Warung Pak Din'), findsOneWidget);
      expect(find.text('Cafeteria A, UTM Skudai'), findsOneWidget);
      expect(find.text('012-345 6781'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('About This Stall'), findsNothing);

      reply.complete(jsonResponse(_vendor()));
      await tester.pumpAndSettle();
      expect(find.text('About This Stall'), findsOneWidget);
      expect(find.text('Home-style rice dishes'), findsOneWidget);
    });

    testWidgets('shows the picture, About This Stall, address and contact', (
      tester,
    ) async {
      final host = await _openPane(
        tester,
        (_) => jsonResponse(_vendor(photoUrl: 'https://cdn/face.jpg')),
      );

      expect(host.server.paths, ['/api/listings/l1/vendor']);
      expect(find.text('Vendor Details'), findsOneWidget);
      expect(find.text('About This Stall'), findsOneWidget);
      expect(find.text('Home-style rice dishes'), findsOneWidget);
      expect(find.text('Cafeteria A, UTM Skudai'), findsOneWidget);
      expect(find.text('012-345 6781'), findsOneWidget);
      expect(find.text(directionsLabel), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
      expect(avatar.photoUrl, 'https://cdn/face.jpg');
      expect(avatar.name, 'Warung Pak Din');
      expect(find.text('More From This Stall'), findsNothing);
      for (final icon in [Icons.storefront, Icons.info_outline]) {
        expect(find.byIcon(icon), findsOneWidget);
      }
    });

    testWidgets('a stall with no picture, description or contact hides them', (
      tester,
    ) async {
      await _openPane(
        tester,
        (_) => jsonResponse(
          _vendor(description: null, phone: null, location: null),
        ),
      );

      expect(find.text('About This Stall'), findsNothing);
      expect(find.text('Contact'), findsNothing);
      expect(find.text('Call'), findsNothing);
      expect(find.text(directionsLabel), findsNothing);
      expect(find.text('Cafeteria A, UTM Skudai'), findsOneWidget);
      expect(find.text('WP'), findsOneWidget);
    });

    testWidgets('Directions and Call open the right apps', (tester) async {
      final links = _Links()..install();
      await _openPane(tester, (_) => jsonResponse(_vendor()));

      await tester.tap(find.byKey(const ValueKey('pane-find-on-maps')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pane-call')));
      await tester.pumpAndSettle();

      expect(links.opened, [_cafeteriaA, Uri.parse('tel:0123456781')]);
      expect(find.byKey(const ValueKey('pane-link-error')), findsNothing);
    });

    testWidgets('a hand-placed pin opens Maps at its coordinates', (
      tester,
    ) async {
      final links = _Links()..install();
      await _openPane(tester, (_) => jsonResponse(_vendor(placeId: null)));

      await tester.tap(find.byKey(const ValueKey('pane-find-on-maps')));
      await tester.pumpAndSettle();
      expect(
        links.opened.single.queryParameters['destination'],
        '1.559,103.6385',
      );
    });

    testWidgets('a link that cannot open says so inside the pane', (
      tester,
    ) async {
      final links = _Links()
        ..works = false
        ..install();
      await _openPane(tester, (_) => jsonResponse(_vendor()));

      await tester.tap(find.byKey(const ValueKey('pane-find-on-maps')));
      await tester.pumpAndSettle();
      expect(find.text(mapsFailed), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pane-call')));
      await tester.pumpAndSettle();
      expect(find.text(phoneFailed), findsOneWidget);
      expect(find.text(mapsFailed), findsNothing);
      expect(links.opened, hasLength(2));
    });

    testWidgets('a gone stall says so with no retry', (tester) async {
      await _openPane(
        tester,
        (_) => jsonResponse({
          'code': 'LISTING_GONE',
          'error': 'This item is no longer available.',
        }, 404),
        listing: _details(),
      );
      expect(find.text(vendorGone), findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
      expect(find.text(directionsLabel), findsNothing);
    });

    testWidgets('a failed load keeps what is known and offers Try Again', (
      tester,
    ) async {
      var calls = 0;
      await _openPane(tester, (_) {
        calls++;
        return calls == 1
            ? jsonResponse({'error': 'boom'}, 500)
            : jsonResponse(_vendor());
      }, listing: _details());
      expect(
        find.text("Unable to load this stall's information."),
        findsOneWidget,
      );
      expect(find.text('Check your connection and try again.'), findsOneWidget);
      final title = tester.widget<Text>(find.text(vendorLoadFailed));
      final hint = tester.widget<Text>(find.text(vendorLoadHint));
      expect(hint.style!.fontSize!, lessThan(title.style!.fontSize!));
      expect(find.text('Cafeteria A, UTM Skudai'), findsOneWidget);

      await tester.tap(find.text('Try Again'));
      await tester.pumpAndSettle();
      expect(find.text('Home-style rice dishes'), findsOneWidget);
      expect(find.text(vendorLoadFailed), findsNothing);
      expect(calls, 2);
    });

    testWidgets('a slow server keeps the spinner until the info arrives', (
      tester,
    ) async {
      await _openPane(
        tester,
        (_) => Future.delayed(
          const Duration(seconds: 15),
          () => jsonResponse(_vendor()),
        ),
        settle: false,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text(vendorLoadFailed), findsNothing);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Home-style rice dishes'), findsOneWidget);
    });

    testWidgets('a server that never answers ends in Try Again', (
      tester,
    ) async {
      await _openPane(
        tester,
        (_) => Completer<http.Response>().future,
        settle: false,
      );
      await tester.pump();
      await tester.pump(ApiConfig.requestTimeout + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(vendorLoadFailed), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets(
      'More From This Stall uses the Running Out Soon card without the stall line',
      (tester) async {
        await _openPane(
          tester,
          (_) => jsonResponse(
            _vendor(
              others: [
                _listing(id: 'l2', title: 'Mee Goreng', stock: 2),
                _listing(id: 'l3', title: 'Kuih Lapis', stock: 9),
              ],
            ),
          ),
        );

        expect(find.text('More From This Stall'), findsOneWidget);
        expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
        final cards = find.descendant(
          of: find.byKey(const ValueKey('more-from-stall')),
          matching: find.byType(ListingCard),
        );
        expect(cards, findsNWidgets(2));
        expect(
          tester.getTopLeft(cards.at(0)).dy,
          tester.getTopLeft(cards.at(1)).dy,
        );
        expect(
          tester.getTopLeft(cards.at(0)).dx,
          lessThan(tester.getTopLeft(cards.at(1)).dx),
        );
        final first = tester.widget<ListingCard>(cards.at(0));
        expect(first.showBadges, isTrue);
        expect(first.onShowVendor, isNull);
        expect(first.inStallPane, isTrue);
        expect(
          find.descendant(
            of: cards.at(0),
            matching: find.textContaining('From '),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: cards.at(0), matching: find.text('2 in stock')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: cards.at(1), matching: find.text('9 in stock')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cards.at(0),
            matching: find.textContaining('Allergens: '),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: cards.at(0),
            matching: find.textContaining('2 left'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('the cards are the same size as Running Out Soon cards', (
      tester,
    ) async {
      await _openPane(
        tester,
        (_) => jsonResponse(
          _vendor(
            others: [
              _listing(id: 'l2', title: 'Mee Goreng'),
              _listing(id: 'l3', title: 'Kuih'),
            ],
          ),
        ),
        size: const Size(411, 900),
      );
      final runningOutWidth = (411 - AppSpacing.md * 2 - AppSpacing.sm) / 2;
      final cards = find.byType(ListingCard);
      expect(cards, findsNWidgets(2));
      for (var index = 0; index < 2; index++) {
        final size = tester.getSize(cards.at(index));
        expect(size.width, closeTo(runningOutWidth, 0.01));
        expect(size.height, ListingCard.browseHeight);
      }
    });

    testWidgets('opening one of them keeps the pane and refreshes it after', (
      tester,
    ) async {
      final host = await _openPane(
        tester,
        (_) => jsonResponse(
          _vendor(
            others: [_listing(id: 'l2', title: 'Mee Goreng')],
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('listing-card-l2')));
      await tester.pumpAndSettle();

      expect(host.openedListings.single.id, 'l2');
      expect(find.byKey(const ValueKey('vendor-pane')), findsOneWidget);
      expect(host.server.vendorCalls, 2);
    });

    testWidgets('a pane opened again within seconds needs no new request', (
      tester,
    ) async {
      final host = await _openPane(tester, (_) => jsonResponse(_vendor()));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pump();
      expect(find.text('Home-style rice dishes'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(host.server.vendorCalls, 1);
    });

    testWidgets('the pane opens above the tab bar', (tester) async {
      _setSize(tester, const Size(800, 1600));
      final server = _Server((_) => jsonResponse(_vendor()));
      final api = server.api;
      final innerKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          ListingRepository(api),
          api,
          Scaffold(
            body: Navigator(
              key: innerKey,
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showVendorPane(
                      context,
                      listing: Listing.fromJson(_listing()),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: const SizedBox(
              height: 80,
              child: Text('tabs'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final pane = tester.element(find.byKey(const ValueKey('vendor-pane')));
      expect(Navigator.of(pane), isNot(innerKey.currentState));
      expect(Navigator.of(pane), Navigator.of(pane, rootNavigator: true));
    });

    testWidgets('Vendor Details is the biggest heading, above the stall name', (
      tester,
    ) async {
      await _openPane(tester, (_) => jsonResponse(_vendor()));
      double sizeOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.fontSize!;
      expect(sizeOf('Vendor Details'), greaterThan(sizeOf('Warung Pak Din')));
      expect(sizeOf('Vendor Details'), greaterThan(sizeOf('About This Stall')));
    });

    testWidgets('the description sits in a box like the pickup details', (
      tester,
    ) async {
      await _openPane(tester, (_) => jsonResponse(_vendor()));
      final box = find.ancestor(
        of: find.text('Home-style rice dishes'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).border != null,
        ),
      );
      expect(box, findsOneWidget);
    });

    testWidgets('Directions and Call sit at the right of their rows', (
      tester,
    ) async {
      await _openPane(tester, (_) => jsonResponse(_vendor()));
      final call = find.byKey(const ValueKey('pane-call'));
      final maps = find.byKey(const ValueKey('pane-find-on-maps'));
      final number = find.text('012-345 6781');
      expect(
        tester.getRect(call).right,
        closeTo(tester.getRect(maps).right, 1),
      );
      expect(
        tester.getCenter(call).dy,
        closeTo(tester.getCenter(number).dy, 12),
      );
      expect(
        tester.getRect(call).left,
        greaterThan(tester.getRect(number).right),
      );
    });

    testWidgets('a long address puts Directions under it, at the right', (
      tester,
    ) async {
      await _openPane(
        tester,
        (_) => jsonResponse(_vendor(address: _longAddress)),
        size: const Size(360, 900),
      );
      final maps = tester.getRect(
        find.byKey(const ValueKey('pane-find-on-maps')),
      );
      final address = tester.getRect(find.text(_longAddress));
      final call = tester.getRect(find.byKey(const ValueKey('pane-call')));
      expect(maps.top, greaterThanOrEqualTo(address.bottom));
      expect(maps.right, closeTo(call.right, 1));
    });

    testWidgets('tapping outside closes the pane', (tester) async {
      await _openPane(tester, (_) => jsonResponse(_vendor()));
      expect(find.byKey(const ValueKey('vendor-pane')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vendor-pane')), findsNothing);
    });

    for (final width in _widths) {
      for (final scale in _scales) {
        testWidgets('long names fit at width $width and text x$scale', (
          tester,
        ) async {
          await _openPane(
            tester,
            (_) => jsonResponse(
              _vendor(
                stall: _longStall,
                address: _longAddress,
                description: 'A' * 400,
                others: [
                  for (final id in ['l2', 'l3', 'l4', 'l5'])
                    _listing(id: id, title: _longTitle, stock: 2),
                ],
              ),
            ),
            size: Size(width, 800),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.text(directionsLabel), findsOneWidget);
          expect(find.byType(ListingCard), findsWidgets);
        });
      }
    }
  });

  group('food details', () {
    testWidgets('the title is Food Details and the stall is not a link', (
      tester,
    ) async {
      await _openDetails(tester);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Food Details'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('stall-title')), findsNothing);
    });

    testWidgets('the Vendor Details card loads early and opens a filled pane', (
      tester,
    ) async {
      final server = await _openDetails(
        tester,
        vendor: _vendor(photoUrl: 'https://cdn/face.jpg'),
      );

      expect(server.vendorCalls, 1);
      final card = find.byType(VendorDetailsCard);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Vendor Details')),
        findsOneWidget,
      );
      final avatar = tester.widget<ProfileAvatar>(
        find.descendant(of: card, matching: find.byType(ProfileAvatar)),
      );
      expect(avatar.photoUrl, 'https://cdn/face.jpg');

      final stall = find.byKey(const ValueKey('vendor-details-card'));
      await tester.ensureVisible(stall);
      await tester.tap(stall);
      await tester.pump();
      expect(find.text('About This Stall'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vendor-pane')), findsOneWidget);
      expect(server.vendorCalls, 1);
    });

    testWidgets('Directions and Call use the stall address and number', (
      tester,
    ) async {
      final links = _Links()..install();
      await _openDetails(tester);

      expect(find.text('Contact'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('details-find-on-maps')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('details-call')));
      await tester.pumpAndSettle();

      expect(links.opened, [_cafeteriaA, Uri.parse('tel:0123456781')]);
    });

    testWidgets(
      'a hand-placed pin uses coordinates, and no number hides Contact',
      (tester) async {
        final links = _Links()..install();
        await _openDetails(
          tester,
          listing: _details(phone: null, placeId: null),
        );

        expect(find.text('Contact'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('details-find-on-maps')));
        await tester.pumpAndSettle();
        expect(
          links.opened.single.queryParameters['destination'],
          '1.559,103.6385',
        );
      },
    );

    testWidgets('a link that cannot open shows a message', (tester) async {
      _Links()
        ..works = false
        ..install();
      await _openDetails(tester);

      await tester.tap(find.byKey(const ValueKey('details-call')));
      await tester.pumpAndSettle();
      expect(find.text(phoneFailed), findsOneWidget);
    });

    for (final (width, scale) in _pageSizes) {
      testWidgets('long stall and address fit at width $width and x$scale', (
        tester,
      ) async {
        await _openDetails(
          tester,
          listing: _details(stall: _longStall, address: _longAddress),
          size: Size(width, 900),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(VendorDetailsCard), findsOneWidget);
      });
    }
  });

  group('cards', () {
    Future<List<String>> pumpCard(
      WidgetTester tester, {
      bool withVendor = true,
    }) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: ListingCard.browseHeight,
                child: ListingCard(
                  listing: Listing.fromJson(_listing()),
                  showBadges: true,
                  onTap: () => calls.add('details'),
                  onShowVendor: withVendor ? () => calls.add('vendor') : null,
                  onPressDown: withVendor ? () => calls.add('down') : null,
                ),
              ),
            ),
          ),
        ),
      );
      return calls;
    }

    testWidgets('a long-press shows the stall', (tester) async {
      final calls = await pumpCard(tester);
      await tester.longPress(find.byKey(const ValueKey('listing-card-l1')));
      expect(calls, ['down', 'vendor']);
    });

    testWidgets('a tap anywhere, the stall line included, opens details', (
      tester,
    ) async {
      final calls = await pumpCard(tester);
      await tester.tap(find.text('From Warung Pak Din'), warnIfMissed: false);
      await tester.tap(find.text('Nasi Lemak'), warnIfMissed: false);
      expect(calls, ['down', 'details', 'down', 'details']);
    });

    testWidgets('a touch starts loading before the tap finishes', (
      tester,
    ) async {
      final calls = await pumpCard(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('listing-card-l1'))),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, ['down']);
      await gesture.up();
      await tester.pump();
      expect(calls, ['down', 'details']);
    });

    testWidgets('without a stall action every tap opens details', (
      tester,
    ) async {
      final calls = await pumpCard(tester, withVendor: false);
      await tester.tap(find.text('From Warung Pak Din'), warnIfMissed: false);
      await tester.longPress(find.byKey(const ValueKey('listing-card-l1')));
      expect(calls, ['details', 'details']);
    });

    testWidgets('search rows show the stall only on long-press', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SearchResultRow(
              listing: Listing.fromJson(_listing()),
              onTap: () => calls.add('details'),
              onShowVendor: () => calls.add('vendor'),
              onPressDown: () => calls.add('down'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('From Warung Pak Din'));
      await tester.tap(find.text('Nasi Lemak'));
      await tester.longPress(find.text('Nasi Lemak'));
      expect(calls, ['down', 'details', 'down', 'details', 'down', 'vendor']);
    });
  });

  group('every size, Android-style text', () {
    for (final width in _widths) {
      for (final scale in _scales) {
        testWidgets('SVS-15 parts fit at width $width and text x$scale', (
          tester,
        ) async {
          final pinned = {
            'pickupLocation': [103.6385, 1.559],
          };
          await _pumpAlone(
            tester,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VendorDetailsCard(stallName: _longStall, onTap: () {}),
                PickupInfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Pickup address',
                  value: _longAddress,
                  actionLabel: directionsLabel,
                  actionIcon: directionsIcon,
                  onAction: () {},
                ),
                PickupInfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Contact',
                  value: '+60 12-345 6781',
                  actionLabel: 'Call',
                  actionIcon: Icons.call_outlined,
                  onAction: () {},
                ),
                CartStallHeading(
                  stallName: _longStall,
                  items: [
                    CartItem.fromJson({
                      ..._cartItem(stall: _longStall),
                      ...pinned,
                    }),
                  ],
                ),
                CartStallHeading(
                  stallName: 'Kopi',
                  items: [
                    CartItem.fromJson({..._cartItem(stall: 'Kopi'), ...pinned}),
                  ],
                ),
              ],
            ),
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          expect(find.text(directionsLabel), findsNWidgets(3));
        });

        testWidgets('search rows with long names fit at $width and x$scale', (
          tester,
        ) async {
          await _pumpAlone(
            tester,
            Column(
              children: [
                for (final halal in [true, false])
                  SearchResultRow(
                    listing: Listing.fromJson(
                      _listing(
                        title: _longTitle,
                        stall: _longStall,
                        extra: {
                          'isHalal': halal,
                          'pickupAddress': 'Cafeteria A, UTM Skudai, Johor',
                        },
                      ),
                    ),
                    onTap: () {},
                    onShowVendor: () {},
                  ),
              ],
            ),
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('the Vendor Details card sits above the item details', (
    tester,
  ) async {
    await _openDetails(tester);
    final card = tester.getRect(find.byType(VendorDetailsCard));
    expect(card.bottom, lessThan(tester.getRect(find.text('Pickup time')).top));
    expect(
      card.top,
      greaterThan(tester.getRect(find.text('With sambal')).bottom),
    );
  });

  testWidgets('the Vendor Details card holds the pickup and contact rows', (
    tester,
  ) async {
    await _openDetails(tester, vendor: _vendor(description: 'Line ' * 80));
    final card = find.byType(VendorDetailsCard);
    for (final text in ['Cafeteria A, UTM Skudai', '012-345 6781']) {
      expect(
        find.descendant(of: card, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: card, matching: find.textContaining('Line Line')),
      findsNothing,
    );
    final vendorSize = tester
        .widget<Text>(
          find.descendant(of: card, matching: find.text('Vendor Details')),
        )
        .style!
        .fontSize!;
    final stallSize = tester
        .widget<Text>(
          find.descendant(of: card, matching: find.text('Warung Pak Din')),
        )
        .style!
        .fontSize!;
    expect(vendorSize, greaterThan(stallSize));
  });

  testWidgets('heading icons line up with their words', (tester) async {
    await _openDetails(tester);
    void lined(Finder within, IconData icon, String text) {
      final iconY = tester
          .getCenter(find.descendant(of: within, matching: find.byIcon(icon)))
          .dy;
      final textY = tester
          .getCenter(find.descendant(of: within, matching: find.text(text)))
          .dy;
      expect(iconY, closeTo(textY, 1), reason: text);
    }

    lined(find.byType(VendorDetailsCard), Icons.info_outline, 'Vendor Details');
    await tester.tap(find.byKey(const ValueKey('vendor-details-card')));
    await tester.pumpAndSettle();
    final pane = find.byKey(const ValueKey('vendor-pane'));
    lined(pane, Icons.storefront, 'Vendor Details');
    lined(pane, Icons.info_outline, 'About This Stall');
  });

  group('cart', () {
    Future<void> pumpCart(
      WidgetTester tester,
      List<Map<String, dynamic>> items, {
      Size size = const Size(800, 1600),
      double textScale = 1,
    }) async {
      _setSize(tester, size);
      final server = _Server(
        (_) => jsonResponse({
          'cart': {'items': items, 'total': 4.5, 'warnings': const []},
        }),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<CartProvider>(
          create: (_) => CartProvider(CartRepository(server.api)),
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => _textScaled(child!, textScale),
            home: Scaffold(body: CartPage(onOrdered: (context, orders) {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('each stall heading opens directions to that stall', (
      tester,
    ) async {
      final links = _Links()..install();
      await pumpCart(tester, [
        {
          ..._cartItem(),
          'pickupAddress': 'Cafeteria A, UTM Skudai',
          'pickupLocation': [103.6385, 1.559],
          'pickupPlaceId': 'place-1',
        },
        {
          ..._cartItem(id: 'l2', stall: 'Second Stall'),
          'pickupLocation': [103.64, 1.56],
        },
        {..._cartItem(id: 'l3', stall: 'No Pin Stall')},
      ]);

      expect(find.text(directionsLabel), findsNWidgets(2));
      final heading = tester.getRect(find.text('From Warung Pak Din'));
      final button = tester.getRect(
        find.byKey(const ValueKey('cart-find-on-maps-Warung Pak Din')),
      );
      expect(button.left, greaterThan(heading.right));
      expect(button.right, greaterThan(700));
      final pill = tester.widget<ActionPill>(
        find.byKey(const ValueKey('cart-find-on-maps-Warung Pak Din')),
      );
      expect(pill.filled, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('cart-find-on-maps-Warung Pak Din')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cart-find-on-maps-Second Stall')),
      );
      await tester.pumpAndSettle();
      expect(links.opened, [
        _cafeteriaA,
        directionsUri(lat: 1.56, lng: 103.64, address: 'Cafeteria A'),
      ]);
    });

    for (final (width, scale) in _pageSizes) {
      testWidgets('a long stall heading fits at width $width and x$scale', (
        tester,
      ) async {
        await pumpCart(
          tester,
          [
            {
              ..._cartItem(stall: _longStall),
              'pickupLocation': [103.6385, 1.559],
            },
          ],
          size: Size(width, 900),
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}

Map<String, dynamic> _cartItem({
  String id = 'l1',
  String stall = 'Warung Pak Din',
}) => {
  'listingId': id,
  'itemName': 'Nasi Lemak',
  'stallName': stall,
  'quantity': 1,
  'unitPrice': 4.5,
  'lineTotal': 4.5,
  'available': true,
  'reason': null,
  'notices': const <String>[],
  'category': 'Rice',
  'pickupAddress': 'Cafeteria A',
  'stockLeft': 5,
  'pickupStart': _inHours(1),
  'pickupEnd': _inHours(3),
};
