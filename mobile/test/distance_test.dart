import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/domain/search_filters.dart';
import 'package:savespoon/features/map/data/position_source.dart';
import 'package:savespoon/features/map/domain/distance.dart';
import 'package:savespoon/features/map/presentation/providers/user_location_provider.dart';
import 'package:savespoon/features/seller_profile/domain/geo_point.dart';

import 'helpers.dart';

const _pakDin = GeoPoint(1.559, 103.6385);
const _cendana = GeoPoint(1.5565, 103.641);

Map<String, dynamic> _listing({String id = 'l1', Object? location}) => {
  '_id': id,
  'title': 'Nasi Lemak',
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': 10,
  'pickupStart': DateTime.now().toUtc().toIso8601String(),
  'pickupEnd': DateTime.now()
      .add(const Duration(hours: 2))
      .toUtc()
      .toIso8601String(),
  'allergens': const <String>[],
  'status': 'active',
  'stallName': 'Warung Pak Din',
  'location': ?location,
};

ListingRepository _repository(List<Uri> sent, Object body) => ListingRepository(
  ApiClient(
    client: MockClient((request) async {
      sent.add(request.url);
      return jsonResponse(body);
    }),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('distance labels', () {
    test('10 m steps under 1 km, one decimal in km, 20+ km beyond', () {
      expect(distanceLabel(0), '10 m');
      expect(distanceLabel(347), '350 m');
      expect(distanceLabel(994), '990 m');
      expect(distanceLabel(996), '1.0 km');
      expect(distanceLabel(1240), '1.2 km');
      expect(distanceLabel(19900), '19.9 km');
      expect(distanceLabel(20000), '20+ km');
      expect(distanceLabel(13000000), '20+ km');
    });

    test('straight-line distance between two campus stalls', () {
      final metres = metresBetween(_pakDin, _cendana);
      expect(metres, closeTo(393, 2));
      expect(metresBetween(_cendana, _pakDin), closeTo(metres, 0.001));
      expect(distanceBetween(_pakDin, _cendana), '390 m');
      expect(distanceBetween(null, _cendana), isNull);
      expect(distanceBetween(_pakDin, null), isNull);
    });
  });

  group('the customer location', () {
    test(
      'a refresh never asks, and keeps no position when not allowed',
      () async {
        final source = FakePositionSource(position: _pakDin, last: _pakDin);
        final location = UserLocationProvider(source);

        await location.refreshIfAllowed();

        expect(source.requests, 0);
        expect(source.watchers, 0);
        expect(location.access, LocationAccess.denied);
        expect(location.position, isNull);
      },
    );

    test('opening the map asks once, shows the last known position at once, then follows the phone', () async {
      final source = FakePositionSource(
        afterRequest: LocationAccess.allowed,
        last: _pakDin,
        position: _cendana,
      );
      final location = UserLocationProvider(source);

      expect(await location.requestAndLocate(), LocationAccess.allowed);
      expect(source.requests, 1);
      expect(source.fixes, 0, reason: 'the last known position was enough');
      expect(location.position, _pakDin);

      source.moves.add(_cendana);
      await pumpEventQueue();
      expect(location.position, _cendana);

      await location.refreshIfAllowed();
      expect(source.watchers, 1, reason: 'follows once');
      location.dispose();
    });

    test('without a last known position, the map waits for one fix', () async {
      final source = FakePositionSource(
        afterRequest: LocationAccess.allowed,
        position: _cendana,
      );
      final location = UserLocationProvider(source);

      await location.requestAndLocate();

      expect(source.fixes, 1);
      expect(location.position, _cendana);
      location.dispose();
    });

    test(
      'already allowed: starting the app follows the phone without asking',
      () async {
        final source = FakePositionSource(
          access: LocationAccess.allowed,
          last: _pakDin,
        );
        final location = UserLocationProvider(source)..start();
        await pumpEventQueue();

        expect(source.requests, 0);
        expect(source.watchers, 1);
        expect(location.position, _pakDin);
        location.dispose();
      },
    );

    test(
      'going to the background stops following; coming back checks again',
      () async {
        final binding = TestWidgetsFlutterBinding.instance;
        final source = FakePositionSource(
          access: LocationAccess.allowed,
          last: _pakDin,
        );
        final location = UserLocationProvider(source)..start();
        await pumpEventQueue();
        expect(source.moves.hasListener, isTrue);

        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          binding.handleAppLifecycleStateChanged(state);
        }
        expect(source.moves.hasListener, isFalse);

        source.access = LocationAccess.deniedForever;
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          binding.handleAppLifecycleStateChanged(state);
        }
        await pumpEventQueue();
        expect(location.access, LocationAccess.deniedForever);
        expect(location.position, isNull);
        location.dispose();
      },
    );

    test(
      'approximate location is noted, and losing permission stops following',
      () async {
        final source = FakePositionSource(
          access: LocationAccess.allowed,
          last: _pakDin,
          approximate: true,
        );
        final location = UserLocationProvider(source);
        await location.refreshIfAllowed();
        expect(location.approximate, isTrue);
        expect(location.position, _pakDin);

        source.access = LocationAccess.denied;
        await location.refreshIfAllowed();
        expect(location.position, isNull);
        expect(source.moves.hasListener, isFalse);
        location.dispose();
      },
    );

    test(
      'tapping the map icon asks once and does not wait for a fix',
      () async {
        final source = FakePositionSource(
          afterRequest: LocationAccess.allowed,
          position: _cendana,
        );
        final location = UserLocationProvider(source);

        expect(await location.askPermission(), LocationAccess.allowed);
        expect(source.requests, 1);
        expect(source.fixes, 0);
        location.dispose();
      },
    );

    test('the map finds the position without ever asking', () async {
      final asked = FakePositionSource(
        access: LocationAccess.allowed,
        position: _cendana,
      );
      final location = UserLocationProvider(asked);
      await location.locate();
      expect(asked.requests, 0);
      expect(location.position, _cendana);
      location.dispose();

      final refused = FakePositionSource(afterRequest: LocationAccess.allowed);
      final none = UserLocationProvider(refused);
      expect(await none.locate(), LocationAccess.denied);
      expect(refused.requests, 0);
    });

    test('location turned off on the phone gives no position', () async {
      final source = FakePositionSource(
        access: LocationAccess.serviceOff,
        position: _pakDin,
      );
      final location = UserLocationProvider(source);
      await location.requestAndLocate();
      expect(location.position, isNull);
      expect(location.access, LocationAccess.serviceOff);
    });
  });

  group('the listing API', () {
    test('browse and search listings carry the stall pin', () {
      final listing = Listing.fromJson(_listing(location: [103.6385, 1.559]));
      expect(listing.pickupLocation, _pakDin);
      expect(Listing.fromJson(_listing()).pickupLocation, isNull);
    });

    test('a location given for Nearest is rounded to about 110 m, and only sent then', () async {
      final sent = <Uri>[];
      final repository = _repository(sent, {'listings': [], 'hasMore': false});

      await repository.search(
        '',
        filters: const SearchFilters(halalOnly: true),
        near: const GeoPoint(1.5590491, 103.6385123),
      );
      await repository.search('nasi');

      expect(sent[0].queryParameters['halal'], '1');
      expect(sent[0].queryParameters['lat'], '1.559');
      expect(sent[0].queryParameters['lng'], '103.639');
      expect(sent[1].queryParameters.containsKey('lat'), isFalse);
    });

    test('the map takes the keyword and filters, never a sort', () async {
      final sent = <Uri>[];
      final repository = _repository(sent, {
        'stalls': [
          {
            'stallName': 'Warung Pak Din',
            'address': 'Cafeteria A',
            'location': [103.6385, 1.559],
            'count': 3,
            'listing': _listing(),
          },
          {'stallName': 'No Pin', 'listing': _listing(id: 'l2')},
        ],
      });

      final stalls = await repository.fetchMap(
        query: ' nasi ',
        filters: const SearchFilters(
          halalOnly: true,
          sort: SearchSort.priceLowToHigh,
        ),
      );
      await repository.fetchMap();

      expect(sent[0].path, '/api/listings/map');
      expect(sent[0].queryParameters, {'q': 'nasi', 'halal': '1'});
      expect(sent[1].query, isEmpty);
      expect(stalls, hasLength(1));
      expect(stalls.single.stallName, 'Warung Pak Din');
      expect(stalls.single.count, 3);
      expect(stalls.single.location, _pakDin);
      expect(stalls.single.listing.id, 'l1');
    });

    test(
      'vendor info from the map asks for all items and is kept apart',
      () async {
        final sent = <Uri>[];
        final repository = _repository(sent, {
          'vendor': {'stallName': 'Warung Pak Din'},
          'otherListings': [_listing()],
        });

        await repository.fetchVendorInfo('l1', all: true);

        expect(
          sent.single.toString(),
          endsWith('/api/listings/l1/vendor?all=1'),
        );
        expect(repository.cachedVendorInfo('l1', all: true), isNotNull);
        expect(repository.cachedVendorInfo('l1'), isNull);
      },
    );
  });
}
