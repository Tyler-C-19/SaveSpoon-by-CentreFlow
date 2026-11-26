import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/features/listings/data/favourites_repository.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/search_filters.dart';
import 'package:savespoon/features/listings/presentation/providers/favourites_provider.dart';

import 'helpers.dart';

class _Server {
  List<String> ids = ['a', 'b'];
  bool failSaves = false;
  bool failIds = false;
  final List<String> calls = [];
  Completer<void>? hold;

  Future<http.Response> handle(http.Request request) async {
    calls.add('${request.method} ${request.url.path}');
    if (request.url.path == '/api/favourites/ids') {
      await hold?.future;
      if (failIds) return jsonResponse({'error': 'Server is down'}, 500);
      return jsonResponse({'listingIds': ids});
    }
    if (failSaves) return jsonResponse({'error': 'Server is down'}, 500);
    return jsonResponse({'favourite': request.method == 'PUT'});
  }
}

FavouritesProvider _provider(_Server server) => FavouritesProvider(
  FavouritesRepository(ApiClient(client: MockClient(server.handle))),
);

void main() {
  test('loads the IDs once per account', () async {
    final server = _Server();
    final favourites = _provider(server);

    await favourites.ensureLoaded('u1');
    await favourites.ensureLoaded('u1');

    expect(favourites.isFavourite('a'), isTrue);
    expect(favourites.isFavourite('c'), isFalse);
    expect(favourites.count, 2);
    expect(server.calls, ['GET /api/favourites/ids']);
  });

  test('another account starts from empty', () async {
    final server = _Server();
    final favourites = _provider(server);
    await favourites.ensureLoaded('u1');

    server.ids = ['c'];
    await favourites.ensureLoaded('u2');

    expect(favourites.isFavourite('a'), isFalse);
    expect(favourites.isFavourite('c'), isTrue);
  });

  test('a failed load is tried again next time', () async {
    final server = _Server()..failIds = true;
    final favourites = _provider(server);

    await favourites.ensureLoaded('u1');
    expect(favourites.count, 0);

    server.failIds = false;
    await favourites.ensureLoaded('u1');
    expect(favourites.count, 2);
  });

  test('a heart changes at once and saves', () async {
    final server = _Server();
    final favourites = _provider(server);
    await favourites.ensureLoaded('u1');
    final before = favourites.changes;

    final adding = favourites.toggle('c');
    expect(favourites.isFavourite('c'), isTrue);
    await adding;
    await favourites.toggle('a');

    expect(favourites.isFavourite('a'), isFalse);
    expect(favourites.changes, before + 2);
    expect(server.calls.skip(1), [
      'PUT /api/favourites/c',
      'DELETE /api/favourites/a',
    ]);
  });

  test('a failed save puts the heart back and passes the error on', () async {
    final server = _Server()..failSaves = true;
    final favourites = _provider(server);
    await favourites.ensureLoaded('u1');

    await expectLater(favourites.toggle('c'), throwsA(isA<ApiException>()));
    expect(favourites.isFavourite('c'), isFalse);
    await expectLater(favourites.toggle('a'), throwsA(isA<ApiException>()));
    expect(favourites.isFavourite('a'), isTrue);
  });

  test('a heart tapped while the IDs load is kept', () async {
    final server = _Server()..hold = Completer<void>();
    final favourites = _provider(server);

    final loading = favourites.ensureLoaded('u1');
    await favourites.toggle('c');
    server.hold!.complete();
    await loading;

    expect(favourites.isFavourite('c'), isTrue);
    expect(favourites.isFavourite('a'), isTrue);
  });

  group('connecting to the API', () {
    late Uri sent;
    late ListingRepository repository;

    setUp(() {
      repository = ListingRepository(
        ApiClient(
          client: MockClient((request) async {
            sent = request.url;
            return jsonResponse({'listings': [], 'hasMore': false});
          }),
        ),
      );
    });

    test('a keyword alone sends only the keyword', () async {
      await repository.search(' nasi ');
      expect(sent.queryParameters, {'q': 'nasi', 'page': '1'});
    });

    test(
      'filters and sort are sent, and the keyword is left out when empty',
      () async {
        await repository.search(
          '',
          page: 2,
          filters: const SearchFilters(
            categories: {'Noodles', 'Rice'},
            halalOnly: true,
            maxPrice: 5,
            avoid: {'milk', 'egg'},
            favouritesOnly: true,
            openNow: true,
            sort: SearchSort.priceLowToHigh,
          ),
        );
        expect(sent.path, '/api/listings/search');
        expect(sent.queryParameters, {
          'category': 'Rice,Noodles',
          'halal': '1',
          'maxPrice': '5.00',
          'avoid': 'egg,milk',
          'favourites': '1',
          'openNow': '1',
          'sort': 'price_asc',
          'page': '2',
        });
      },
    );

    test('Best Match is not sent without a keyword', () async {
      await repository.search(
        '',
        filters: const SearchFilters(
          categories: {'Rice'},
          sort: SearchSort.bestMatch,
        ),
      );
      expect(sent.queryParameters.containsKey('sort'), isFalse);

      await repository.search(
        'nasi',
        filters: const SearchFilters(sort: SearchSort.bestMatch),
      );
      expect(sent.queryParameters['sort'], 'best');
    });

    test('the Favourites strip has its own address', () async {
      await repository.fetchFavourites();
      expect(sent.path, '/api/listings/favourites');
    });
  });

  test('adding sends an empty JSON body the server accepts', () async {
    late http.Request sent;
    final repository = FavouritesRepository(
      ApiClient(
        client: MockClient((request) async {
          sent = request;
          return jsonResponse({'favourite': true});
        }),
      ),
    );

    await repository.add('l1');

    expect(sent.method, 'PUT');
    expect(sent.url.path, '/api/favourites/l1');
    expect(sent.body, '{}');
  });
}
