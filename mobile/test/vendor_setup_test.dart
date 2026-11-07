import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/routing/app_router.dart';
import 'package:savespoon/features/auth/data/auth_repository.dart';
import 'package:savespoon/features/auth/domain/auth_user.dart';
import 'package:savespoon/features/auth/presentation/providers/auth_provider.dart';
import 'package:savespoon/features/home/presentation/pages/home_page.dart';
import 'package:savespoon/features/seller_profile/data/location_service.dart';
import 'package:savespoon/features/seller_profile/data/vendor_repository.dart';
import 'package:savespoon/features/seller_profile/domain/geo_point.dart';
import 'package:savespoon/features/seller_profile/domain/vendor_validators.dart';
import 'package:savespoon/features/seller_profile/presentation/pages/vendor_setup_page.dart';
import 'package:savespoon/features/seller_profile/presentation/widgets/place_search_field.dart';

import 'helpers.dart';

class FakeLocationService implements LocationService {
  FakeLocationService(this.result, {this.address});

  final GeoPoint? result;
  final String? address;
  int calls = 0;

  @override
  Future<GeoPoint?> currentLocation() async {
    calls++;
    return result;
  }

  @override
  Future<String?> addressAt(GeoPoint point) async => address;
}

class SlowLocationService implements LocationService {
  final Completer<GeoPoint?> position = Completer();

  @override
  Future<GeoPoint?> currentLocation() => position.future;

  @override
  Future<String?> addressAt(GeoPoint point) async => 'Arked Meranti, Skudai';
}

class QueuedAddressService implements LocationService {
  final List<Completer<String?>> lookups = [];

  @override
  Future<GeoPoint?> currentLocation() async => null;

  @override
  Future<String?> addressAt(GeoPoint point) {
    final lookup = Completer<String?>();
    lookups.add(lookup);
    return lookup.future;
  }
}

const tappedPoint = GeoPoint(1.5, 103.6);

final vendorJson = <String, dynamic>{
  ...userJson,
  'role': 'vendor',
  'phone': '012-3456789',
  'hasVendorProfile': false,
};

Finder field(String label) => find.widgetWithText(TextFormField, label);

Widget fakeMap(
  BuildContext context,
  GeoPoint target,
  GeoPoint? pin,
  ValueChanged<GeoPoint> onTap,
) => Column(
  children: [
    Text('target ${target.lat},${target.lng}'),
    TextButton(onPressed: () => onTap(tappedPoint), child: const Text('map')),
  ],
);

void main() {
  group('resolveRedirect', () {
    String? redirect(String location, {bool needs = false, String? role}) =>
        resolveRedirect(
          location: location,
          signedIn: true,
          role: role,
          needsVendorSetup: needs,
        );

    test('holds a vendor with no profile on the setup page', () {
      for (final location in [
        AppRoutes.vendorHome,
        AppRoutes.vendorListings,
        AppRoutes.login,
        AppRoutes.verifyEmail,
        AppRoutes.completeGoogle,
      ]) {
        expect(
          redirect(location, needs: true, role: 'vendor'),
          AppRoutes.vendorSetup,
        );
      }
      expect(
        redirect(AppRoutes.vendorSetup, needs: true, role: 'vendor'),
        isNull,
      );
    });

    test('sends everyone else away from the setup page', () {
      expect(
        redirect(AppRoutes.vendorSetup, role: 'vendor'),
        AppRoutes.vendorHome,
      );
      expect(
        redirect(AppRoutes.vendorSetup, role: 'customer'),
        AppRoutes.customerHome,
      );
    });
  });

  test('needsVendorSetup is true only for a vendor with no profile', () {
    AuthUser user(String role, bool has) => AuthUser(
      id: 'u1',
      name: 'Test',
      email: 'a@example.com',
      role: role,
      hasVendorProfile: has,
    );
    expect(user('vendor', false).needsVendorSetup, isTrue);
    expect(user('vendor', true).needsVendorSetup, isFalse);
    expect(user('customer', false).needsVendorSetup, isFalse);
  });

  test('a pin is sent as longitude then latitude', () {
    expect(const GeoPoint(1.5, 103.6).toGeoJson(), {
      'type': 'Point',
      'coordinates': [103.6, 1.5],
    });
  });

  test('validators match the backend limits', () {
    expect(VendorValidators.businessName('A'), isNotNull);
    expect(VendorValidators.businessName('AB'), isNull);
    expect(VendorValidators.businessName('A' * 81), isNotNull);
    expect(VendorValidators.address(' '), isNotNull);
    expect(VendorValidators.address('A' * 200), isNull);
    expect(VendorValidators.address('A' * 201), isNotNull);
    expect(VendorValidators.description(''), isNull);
    expect(VendorValidators.description('A' * 500), isNull);
    expect(VendorValidators.description('A' * 501), isNotNull);
  });

  group('setup page', () {
    late List<http.Request> requests;
    late FakeTokenStorage storage;
    late AuthProvider auth;
    late MockClientHandler respond;

    Future<void> pumpPage(
      WidgetTester tester, {
      LocationService? location,
    }) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      requests = [];
      final api = ApiClient(
        client: MockClient((request) {
          requests.add(request);
          return respond(request);
        }),
        tokenReader: storage.readToken,
      );
      auth = AuthProvider()
        ..attach(
          AuthRepository(api: api, storage: storage),
          FakeGoogleAuth(),
        );
      await auth.restoreSession();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            Provider<VendorRepository>.value(value: VendorRepository(api)),
          ],
          child: MaterialApp(
            home: VendorSetupPage(
              mapBuilder: fakeMap,
              locationService: location ?? FakeLocationService(null),
            ),
          ),
        ),
      );
      requests.clear();
    }

    Future<void> fillForm(WidgetTester tester) async {
      await tester.enterText(field('Business name'), 'Warung Test');
      await tester.enterText(field('Pickup address'), 'K9');
    }

    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Save and continue'));
      await tester.pumpAndSettle();
    }

    setUp(() {
      storage = FakeTokenStorage(token: 'saved');
      respond = (request) async => jsonResponse({'user': vendorJson});
    });

    testWidgets('starts the contact number with the account phone', (
      tester,
    ) async {
      await pumpPage(tester);
      expect(find.text('012-3456789'), findsOneWidget);
    });

    testWidgets('opens the map on UTM Skudai', (tester) async {
      await pumpPage(tester);
      expect(find.text('target 1.559,103.6385'), findsOneWidget);
    });

    testWidgets('a missing pin or bad field saves nothing', (tester) async {
      await pumpPage(tester);
      await save(tester);
      expect(find.text('Set your pickup location to continue.'), findsOneWidget);
      expect(
        find.text('Business name must be 2 to 80 characters.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);

      await fillForm(tester);
      await save(tester);
      expect(find.text('Set your pickup location to continue.'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('saving sends the profile and ends the setup', (tester) async {
      await pumpPage(tester);
      expect(auth.user!.needsVendorSetup, isTrue);
      respond = (request) async => jsonResponse({'vendor': {}}, 201);

      await fillForm(tester);
      await tester.tap(find.text('map'));
      await tester.pump();
      await save(tester);

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(requests.single.url.path, '/api/vendors/me');
      expect(body['stallName'], 'Warung Test');
      expect(body['phone'], '012-3456789');
      expect(body['address'], 'K9');
      expect(body.containsKey('description'), isFalse);
      expect(body['location']['coordinates'], [103.6, 1.5]);
      expect(auth.user!.needsVendorSetup, isFalse);
      expect(jsonDecode(storage.userJson!)['hasVendorProfile'], isTrue);
    });

    testWidgets('a server error stays on setup and shows the message', (
      tester,
    ) async {
      await pumpPage(tester);
      respond = (request) async => jsonResponse({'error': 'Nope'}, 400);

      await fillForm(tester);
      await tester.tap(find.text('map'));
      await tester.pump();
      await save(tester);

      expect(find.text('Nope'), findsOneWidget);
      expect(auth.user!.needsVendorSetup, isTrue);
    });

    testWidgets('an existing profile ends the setup', (tester) async {
      await pumpPage(tester);
      respond = (request) async => jsonResponse({'error': 'Exists'}, 409);

      await fillForm(tester);
      await tester.tap(find.text('map'));
      await tester.pump();
      await save(tester);

      expect(auth.user!.needsVendorSetup, isFalse);
    });

    testWidgets('current location is requested only on tap and moves the map', (
      tester,
    ) async {
      final location = FakeLocationService(
        const GeoPoint(2, 104),
        address: 'Arked Meranti, Skudai',
      );
      await pumpPage(tester, location: location);
      expect(location.calls, 0);

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      expect(location.calls, 1);
      expect(find.text('target 2.0,104.0'), findsOneWidget);
      expect(find.text('Pin placed. Tap the map to move it.'), findsOneWidget);
    });

    testWidgets('tapping the map fills the address without searching', (
      tester,
    ) async {
      await pumpPage(
        tester,
        location: FakeLocationService(null, address: 'Jalan Meranti, Skudai'),
      );
      await tester.enterText(field('Pickup address'), 'K9');

      await tester.tap(find.text('map'));
      await tester.pumpAndSettle();
      await tester.pump(PlaceSearchField.typingPause);

      expect(find.text('Jalan Meranti, Skudai'), findsOneWidget);
      expect(find.text('K9'), findsNothing);
      expect(requests, isEmpty);
    });

    testWidgets('a failed lookup after a tap keeps the typed address', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.enterText(field('Pickup address'), 'K9');

      await tester.tap(find.text('map'));
      await tester.pumpAndSettle();

      expect(find.text('K9'), findsOneWidget);
      expect(find.text('Pin placed. Tap the map to move it.'), findsOneWidget);
      expect(find.textContaining("Couldn't find the address"), findsOneWidget);
    });

    testWidgets('when taps overlap, the last one sets the address', (
      tester,
    ) async {
      final location = QueuedAddressService();
      await pumpPage(tester, location: location);

      await tester.tap(find.text('map'));
      await tester.pump();
      await tester.tap(find.text('map'));
      await tester.pump();

      location.lookups[1].complete('Second place');
      await tester.pumpAndSettle();
      location.lookups[0].complete('First place');
      await tester.pumpAndSettle();

      expect(find.text('Second place'), findsOneWidget);
      expect(find.text('First place'), findsNothing);
    });

    testWidgets('the location button shows progress while it works', (
      tester,
    ) async {
      final location = SlowLocationService();
      await pumpPage(tester, location: location);

      await tester.tap(find.text('Use my current location'));
      await tester.pump();

      expect(find.text('Finding your location…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Use my current location'), findsNothing);

      location.position.complete(const GeoPoint(2, 104));
      await tester.pumpAndSettle();

      expect(find.text('Use my current location'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('current location fills the address without searching', (
      tester,
    ) async {
      await pumpPage(
        tester,
        location: FakeLocationService(
          const GeoPoint(2, 104),
          address: 'Arked Meranti, Skudai',
        ),
      );

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      await tester.pump(PlaceSearchField.typingPause);

      expect(find.text('Arked Meranti, Skudai'), findsOneWidget);
      expect(requests, isEmpty);
    });

    testWidgets('a failed address lookup still moves the map', (tester) async {
      await pumpPage(
        tester,
        location: FakeLocationService(const GeoPoint(2, 104)),
      );

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();

      expect(find.text('target 2.0,104.0'), findsOneWidget);
      expect(find.textContaining("Couldn't find the address"), findsOneWidget);
    });

    Future<void> chooseSuggestion(WidgetTester tester) async {
      respond = (request) async {
        if (request.method == 'POST') return jsonResponse({'vendor': {}}, 201);
        return request.url.path.endsWith('/location')
            ? jsonResponse({
                'location': {'lat': 1.6, 'lng': 103.7},
              })
            : jsonResponse({
                'suggestions': [
                  {'placeId': 'p1', 'text': 'UTM Skudai'},
                ],
              });
      };
      await tester.enterText(field('Business name'), 'Warung Test');
      await tester.enterText(field('Pickup address'), 'utm');
      await tester.pump(PlaceSearchField.typingPause);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'UTM Skudai'));
      await tester.pumpAndSettle();
    }

    testWidgets('choosing a suggestion is enough to save, with no map tap', (
      tester,
    ) async {
      await pumpPage(tester);
      await chooseSuggestion(tester);
      await save(tester);

      final post = requests.singleWhere((r) => r.method == 'POST');
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['address'], 'UTM Skudai');
      expect(body['placeId'], 'p1');
      expect(body['location']['coordinates'], [103.7, 1.6]);
    });

    testWidgets('tapping the map after a suggestion replaces the place', (
      tester,
    ) async {
      await pumpPage(tester);
      await chooseSuggestion(tester);
      await tester.tap(find.text('map'));
      await tester.pump();
      await save(tester);

      final post = requests.singleWhere((r) => r.method == 'POST');
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['address'], 'UTM Skudai');
      expect(body.containsKey('placeId'), isFalse);
      expect(body['location']['coordinates'], [103.6, 1.5]);
    });

    testWidgets('a refused location permission still allows a pin', (
      tester,
    ) async {
      await pumpPage(tester);

      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't get your location"), findsOneWidget);

      await tester.tap(find.text('map'));
      await tester.pump();
      expect(find.text('Pin placed. Tap the map to move it.'), findsOneWidget);
    });

    testWidgets('choosing a suggestion moves the map and places the pin', (
      tester,
    ) async {
      await pumpPage(tester);
      respond = (request) async => request.url.path.endsWith('/location')
          ? jsonResponse({
              'location': {'lat': 1.6, 'lng': 103.7},
            })
          : jsonResponse({
              'suggestions': [
                {'placeId': 'p1', 'text': 'UTM Skudai'},
              ],
            });

      await tester.enterText(field('Pickup address'), 'utm');
      await tester.pump(PlaceSearchField.typingPause);
      await tester.pumpAndSettle();

      expect(find.text('Google Maps'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'UTM Skudai'));
      await tester.pumpAndSettle();

      expect(find.text('target 1.6,103.7'), findsOneWidget);
      expect(find.text('Google Maps'), findsNothing);
      expect(find.text('Pin placed. Tap the map to move it.'), findsOneWidget);
      expect(
        requests.first.url.queryParameters['sessionToken'],
        requests.last.url.queryParameters['sessionToken'],
      );
    });

    testWidgets('typing fast sends one search, and short text sends none', (
      tester,
    ) async {
      await pumpPage(tester);
      respond = (request) async => jsonResponse({'suggestions': []});

      await tester.enterText(field('Pickup address'), 'ut');
      await tester.pump(PlaceSearchField.typingPause);
      expect(requests, isEmpty);

      await tester.enterText(field('Pickup address'), 'utm');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(field('Pickup address'), 'utm s');
      await tester.pump(PlaceSearchField.typingPause);
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.url.queryParameters['q'], 'utm s');
    });

    testWidgets('a failed search shows a message and the map still works', (
      tester,
    ) async {
      await pumpPage(tester);
      respond = (request) async =>
          jsonResponse({'error': 'Search unavailable'}, 503);

      await tester.enterText(field('Pickup address'), 'utm');
      await tester.pump(PlaceSearchField.typingPause);
      await tester.pumpAndSettle();
      expect(find.text('Search unavailable'), findsOneWidget);

      await tester.tap(find.text('map'));
      await tester.pump();
      expect(find.text('Pin placed. Tap the map to move it.'), findsOneWidget);
    });
  });

  group('in the app', () {
    Map<String, dynamic> vendor({required bool hasProfile}) => {
      ...vendorJson,
      'hasVendorProfile': hasProfile,
    };

    MockClientHandler server({
      required bool hasProfile,
      String description = '',
      List<http.Request>? log,
    }) => (request) async {
      log?.add(request);
      if (request.url.path == '/api/vendors/me') {
        return jsonResponse({
          'vendor': {'description': description},
        });
      }
      return jsonResponse({'user': vendor(hasProfile: hasProfile)});
    };

    testWidgets('a vendor with no profile cannot reach the tabs', (
      tester,
    ) async {
      await startApp(
        tester,
        storage: FakeTokenStorage(token: 'saved'),
        onRequest: server(hasProfile: false),
      );

      expect(find.text('Set up your business'), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      expect(find.text('Listings'), findsNothing);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('a customer never sees setup or the banner', (tester) async {
      final log = <http.Request>[];
      await startApp(
        tester,
        storage: FakeTokenStorage(token: 'saved'),
        onRequest: (request) async {
          log.add(request);
          return jsonResponse({'user': userJson});
        },
      );

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('Set up your business'), findsNothing);
      expect(log.where((r) => r.url.path == '/api/vendors/me'), isEmpty);
    });

    testWidgets('the banner shows while the description is empty', (
      tester,
    ) async {
      await startApp(
        tester,
        storage: FakeTokenStorage(token: 'saved'),
        onRequest: server(hasProfile: true),
      );
      expect(find.textContaining('Add a description'), findsOneWidget);
    });

    testWidgets('the banner stays away once there is a description', (
      tester,
    ) async {
      await startApp(
        tester,
        storage: FakeTokenStorage(token: 'saved'),
        onRequest: server(hasProfile: true, description: 'Rice'),
      );
      expect(find.textContaining('Add a description'), findsNothing);
    });

    testWidgets('dismissing hides the banner until the app reopens', (
      tester,
    ) async {
      final storage = FakeTokenStorage(token: 'saved');
      await startApp(
        tester,
        storage: storage,
        onRequest: server(hasProfile: true),
      );

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.textContaining('Add a description'), findsNothing);

      await tester.tap(find.text('Listings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add a description'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await startApp(
        tester,
        storage: storage,
        onRequest: server(hasProfile: true),
      );
      expect(find.textContaining('Add a description'), findsOneWidget);
    });

    testWidgets('the banner form saves only the description', (tester) async {
      final log = <http.Request>[];
      await startApp(
        tester,
        storage: FakeTokenStorage(token: 'saved'),
        onRequest: server(hasProfile: true, log: log),
      );

      await tester.tap(find.textContaining('Add a description'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a description.'), findsOneWidget);
      expect(log.where((r) => r.method == 'PATCH'), isEmpty);

      await tester.enterText(field('Description'), ' Rice and noodles ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final patch = log.singleWhere((r) => r.method == 'PATCH');
      expect(jsonDecode(patch.body), {'description': 'Rice and noodles'});
      expect(find.textContaining('Add a description'), findsNothing);
    });
  });
}
