import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/features/auth/data/google_auth_service.dart';
import 'package:savespoon/features/auth/data/token_storage.dart';
import 'package:savespoon/features/auth/presentation/pages/splash_page.dart';
import 'package:savespoon/features/listings/data/favourites_repository.dart';
import 'package:savespoon/features/listings/presentation/providers/favourites_provider.dart';
import 'package:savespoon/features/map/data/position_source.dart';
import 'package:savespoon/features/seller_profile/domain/geo_point.dart';
import 'package:savespoon/main.dart';

class FakeTokenStorage implements TokenStorage {
  FakeTokenStorage({this.token, this.userJson});

  String? token;
  String? userJson;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readUserJson() async => userJson;

  @override
  Future<void> save({required String token, required String userJson}) async {
    this.token = token;
    this.userJson = userJson;
  }

  @override
  Future<void> clear() async {
    token = null;
    userJson = null;
  }
}

class FakeGoogleAuth implements GoogleAuthService {
  FakeGoogleAuth({this.idToken});

  String? idToken;
  int signOuts = 0;

  @override
  Future<String?> getIdToken() async => idToken;

  @override
  Future<void> signOut() async => signOuts++;
}

// Stands in for the phone's location; nothing is allowed unless a test says so.
class FakePositionSource implements PositionSource {
  FakePositionSource({
    this.access = LocationAccess.denied,
    this.afterRequest,
    this.position,
    this.last,
    this.approximate = false,
  });

  LocationAccess access;
  // What the permission prompt changes [access] to.
  LocationAccess? afterRequest;
  GeoPoint? position;
  // The phone's last known position, returned at once.
  GeoPoint? last;
  bool approximate;
  // Positions the phone reports as it moves.
  final StreamController<GeoPoint> moves = StreamController.broadcast();
  int watchers = 0;
  int requests = 0;
  int fixes = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;

  @override
  Future<LocationAccess> check() async => access;

  @override
  Future<LocationAccess> request() async {
    requests++;
    access = afterRequest ?? access;
    return access;
  }

  @override
  Future<GeoPoint?> current() async {
    fixes++;
    return position;
  }

  @override
  Future<GeoPoint?> lastKnown() async => last;

  @override
  Stream<GeoPoint> watch() {
    watchers++;
    return moves.stream;
  }

  @override
  Future<bool> isApproximate() async => approximate;

  @override
  Future<void> openAppSettings() async => appSettingsOpened++;

  @override
  Future<void> openLocationSettings() async => locationSettingsOpened++;
}

const userJson = {
  '_id': 'u1',
  'name': 'Test Person',
  'email': 'person@example.com',
  'role': 'customer',
};

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Future<void> startApp(
  WidgetTester tester, {
  required FakeTokenStorage storage,
  required MockClientHandler onRequest,
  GoogleAuthService? googleAuth,
  bool stubBrowse = true,
  PositionSource? positionSource,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    SaveSpoonApp(
      storage: storage,
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/health') {
          return jsonResponse({'status': 'ok'});
        }
        if (request.url.path == '/api/orders/again') {
          return jsonResponse({'listings': []});
        }
        const browsePaths = {'/api/listings', '/api/listings/running-out'};
        if (stubBrowse && request.method == 'GET') {
          if (browsePaths.contains(request.url.path)) {
            return jsonResponse({'listings': []});
          }
          if (request.url.path == '/api/listings/favourites') {
            return jsonResponse({'listings': []});
          }
          if (request.url.path == '/api/favourites/ids') {
            return jsonResponse({'listingIds': []});
          }
          if (request.url.path == '/api/cart') {
            return jsonResponse({
              'cart': {'items': [], 'total': 0, 'warnings': []},
            });
          }
        }
        return onRequest(request);
      }),
      googleAuth: googleAuth ?? FakeGoogleAuth(),
      positionSource: positionSource ?? FakePositionSource(),
    ),
  );
  await tester.pump();
  await tester.pump(SplashPage.displayTime);
  await tester.pumpAndSettle();
}

// The Favourites provider for tests that build a page on its own.
ChangeNotifierProvider<FavouritesProvider> favouritesProvider(
  MockClientHandler onRequest,
) => ChangeNotifierProvider<FavouritesProvider>(
  create: (_) => FavouritesProvider(
    FavouritesRepository(ApiClient(client: MockClient(onRequest))),
  ),
);

// Answers the Favourites requests with none, and passes everything else on.
MockClientHandler withNoFavourites(MockClientHandler onRequest) =>
    (request) async {
      final path = request.url.path;
      if (path == '/api/listings/favourites') {
        return jsonResponse({'listings': []});
      }
      if (path == '/api/favourites/ids') {
        return jsonResponse({'listingIds': []});
      }
      return onRequest(request);
    };
