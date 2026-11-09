import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/pages/customer_home_page.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_card.dart';
import 'package:savespoon/features/listings/presentation/widgets/running_out_strip.dart';

import 'helpers.dart';

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Map<String, dynamic> _listing({
  String id = 'l1',
  String title = 'Nasi Lemak',
  int stock = 10,
  String status = 'active',
  int endsInHours = 3,
  String? createdAt,
}) => {
  '_id': id,
  'createdAt': ?createdAt,
  'title': title,
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': stock,
  'pickupStart': _inHours(endsInHours - 2),
  'pickupEnd': _inHours(endsInHours),
  'allergens': const <String>[],
  'otherAllergens': const <String>[],
  'status': status,
  'stallName': 'Warung Pak Din',
};

Future<void> _pump(
  WidgetTester tester,
  MockClientHandler onRequest, {
  Size size = const Size(800, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Provider<ListingRepository>(
      create: (_) =>
          ListingRepository(ApiClient(client: MockClient(onRequest))),
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: CustomerHomePage(name: 'Aina')),
      ),
    ),
  );
}

MockClientHandler _server({
  List<Map<String, dynamic>> listings = const [],
  List<Map<String, dynamic>> runningOut = const [],
}) => (request) async {
  if (request.url.path.endsWith('/running-out')) {
    return jsonResponse({'listings': runningOut});
  }
  return jsonResponse({'listings': listings, 'hasMore': false});
};

void main() {
  testWidgets('shows the greeting and listings in the order received', (
    tester,
  ) async {
    await _pump(
      tester,
      _server(
        listings: [
          _listing(id: 'a', title: 'Newest'),
          _listing(id: 'b', title: 'Older'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back, Aina'), findsOneWidget);
    expect(
      find.text("Grab affordable meals before they're gone!"),
      findsOneWidget,
    );
    expect(find.text("What's New"), findsOneWidget);
    expect(find.text('From Warung Pak Din'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Newest')).dx,
      lessThan(tester.getTopLeft(find.text('Older')).dx),
    );
  });

  testWidgets('a long name moves to the next line whole', (tester) async {
    Future<void> pumpName(String name, double width) => tester.pumpWidget(
      Provider<ListingRepository>(
        create: (_) =>
            ListingRepository(ApiClient(client: MockClient(_server()))),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: CustomerHomePage(name: name),
              ),
            ),
          ),
        ),
      ),
    );

    await pumpName('Aina', 800);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back, Aina'), findsOneWidget);

    await pumpName('Tyler Chok Ke Qing', 400);
    await tester.pumpAndSettle();
    expect(find.text('Welcome back,\nTyler Chok Ke Qing'), findsOneWidget);
  });

  testWidgets('shows placeholders while loading', (tester) async {
    await _pump(tester, _server());

    expect(find.byKey(const ValueKey('listing-placeholder')), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-placeholder')), findsNothing);
  });

  testWidgets('shows a message when nothing is available', (tester) async {
    await _pump(tester, _server());
    await tester.pumpAndSettle();

    expect(find.text('No food available right now'), findsOneWidget);
    expect(find.text('Running Out Soon'), findsNothing);
  });

  testWidgets('never shows closed or out-of-stock listings', (tester) async {
    await _pump(
      tester,
      _server(
        listings: [
          _listing(id: 'a', title: 'Open'),
          _listing(id: 'b', title: 'Closed', endsInHours: -1),
          _listing(id: 'c', title: 'Empty', stock: 0),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
    expect(find.text('Empty'), findsNothing);
    expect(find.textContaining('Unlisted'), findsNothing);
  });

  testWidgets('shows an error and tries again', (tester) async {
    var fail = true;
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/running-out')) {
        return jsonResponse({'listings': []});
      }
      if (fail) return jsonResponse({'error': 'Server is down'}, 500);
      return jsonResponse({
        'listings': [_listing()],
        'hasMore': false,
      });
    });
    await tester.pumpAndSettle();

    expect(find.text('Server is down'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Server is down'), findsNothing);
    expect(find.text('Nasi Lemak'), findsOneWidget);
  });

  testWidgets('a failed strip does not hide the listings', (tester) async {
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/running-out')) {
        return jsonResponse({'error': 'Failed'}, 500);
      }
      return jsonResponse({
        'listings': [_listing()],
        'hasMore': false,
      });
    });
    await tester.pumpAndSettle();

    expect(find.text('Nasi Lemak'), findsOneWidget);
    expect(find.text('Running Out Soon'), findsNothing);
  });

  testWidgets('pull to refresh fetches the listings again', (tester) async {
    var title = 'Before';
    await _pump(tester, (request) async {
      if (request.url.path.endsWith('/running-out')) {
        return jsonResponse({'listings': []});
      }
      return jsonResponse({
        'listings': [_listing(title: title)],
        'hasMore': false,
      });
    });
    await tester.pumpAndSettle();

    title = 'After';
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 500),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
  });

  testWidgets('a failed refresh keeps the listings on screen', (tester) async {
    var fail = false;
    await _pump(tester, (request) async {
      if (fail) return jsonResponse({'error': 'Server is down'}, 500);
      if (request.url.path.endsWith('/running-out')) {
        return jsonResponse({'listings': []});
      }
      return jsonResponse({
        'listings': [_listing()],
        'hasMore': false,
      });
    });
    await tester.pumpAndSettle();

    fail = true;
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 500),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('Nasi Lemak'), findsOneWidget);
    expect(find.text('Server is down'), findsOneWidget);
  });

  group('paging', () {
    List<Map<String, dynamic>> pageOf(int page, {int count = 20}) => [
      for (var i = 0; i < count; i++)
        _listing(id: 'p$page-$i', title: 'Page $page item $i'),
    ];

    testWidgets('fetches the next page on scroll without repeats', (
      tester,
    ) async {
      final pages = <String>[];
      await _pump(tester, (request) async {
        if (request.url.path.endsWith('/running-out')) {
          return jsonResponse({'listings': []});
        }
        final page = request.url.queryParameters['page']!;
        pages.add(page);
        return jsonResponse({
          'listings': [
            if (page == '2') _listing(id: 'p1-0', title: 'Repeat'),
            ...pageOf(int.parse(page), count: page == '1' ? 20 : 1),
          ],
          'hasMore': page == '1',
        });
      }, size: const Size(800, 800));
      await tester.pumpAndSettle();
      expect(pages, ['1']);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
      await tester.pumpAndSettle();
      expect(pages, ['1', '2']);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
      await tester.pumpAndSettle();
      expect(pages, ['1', '2'], reason: 'no further pages');
      expect(find.text('Page 2 item 0'), findsOneWidget);
      expect(find.text('Repeat'), findsNothing);
    });

    testWidgets('a failed page offers a retry and keeps the list', (
      tester,
    ) async {
      var fail = true;
      await _pump(tester, (request) async {
        if (request.url.path.endsWith('/running-out')) {
          return jsonResponse({'listings': []});
        }
        final page = request.url.queryParameters['page']!;
        if (page == '2' && fail) {
          return jsonResponse({'error': 'Server is down'}, 500);
        }
        return jsonResponse({
          'listings': pageOf(int.parse(page), count: page == '1' ? 20 : 1),
          'hasMore': page == '1',
        });
      }, size: const Size(800, 800));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(find.text('Server is down'), findsOneWidget);

      fail = false;
      await tester.ensureVisible(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Server is down'), findsNothing);
      expect(find.text('Page 2 item 0'), findsOneWidget);
    });
  });

  group('low stock', () {
    testWidgets('the ribbon shows at 5 and not at 6', (tester) async {
      await _pump(
        tester,
        _server(
          listings: [
            _listing(id: 'a', stock: 5),
            _listing(id: 'b', stock: 6),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Only 5 left!'), findsOneWidget);
      expect(find.text('Only 6 left!'), findsNothing);
    });

    testWidgets('customers see no stock line', (tester) async {
      await _pump(
        tester,
        _server(
          listings: [
            _listing(id: 'a', stock: 5),
            _listing(id: 'b', stock: 6),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('in stock'), findsNothing);
    });

    testWidgets('Running Out Soon shows the listings from the server', (
      tester,
    ) async {
      await _pump(
        tester,
        _server(
          listings: [_listing(id: 'a', title: 'Grid item')],
          runningOut: [_listing(id: 'b', title: 'Strip item', stock: 2)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Running Out Soon'), findsOneWidget);
      expect(find.text('Strip item'), findsOneWidget);
      expect(find.text('Only 2 left!'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Only 2 left!')).dy,
        lessThan(tester.getTopLeft(find.text('Strip item')).dy),
        reason: 'the image area sits above the text',
      );
      final cards = find.byType(ListingCard);
      expect(cards, findsNWidgets(2));
      expect(find.byType(RunningOutStrip), findsOneWidget);
      expect(tester.getSize(cards.first), tester.getSize(cards.last));
      expect(
        tester.getTopLeft(find.text('Running Out Soon')).dy,
        lessThan(tester.getTopLeft(find.text("What's New")).dy),
      );
    });
  });

  group('ListingCard', () {
    Future<void> pumpCard(
      WidgetTester tester,
      Map<String, dynamic> json, {
      bool showBadges = false,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 400,
            child: ListingCard(
              listing: Listing.fromJson(json),
              showBadges: showBadges,
            ),
          ),
        ),
      ),
    );

    testWidgets('a vendor sees no low-stock ribbon', (tester) async {
      await pumpCard(tester, _listing(stock: 2));

      expect(find.text('Only 2 left!'), findsNothing);
      expect(find.text('2 in stock'), findsOneWidget);
      expect(find.textContaining('Unlisted'), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('unlisted cards say why and are greyed out', (tester) async {
      for (final (json, label) in [
        (_listing(endsInHours: -1), 'Unlisted - Pickup Ended'),
        (_listing(stock: 0), 'Unlisted - No Stock'),
        (_listing(status: 'sold_out'), 'Unlisted - No Stock'),
        (_listing(status: 'cancelled'), 'Unlisted'),
      ]) {
        await pumpCard(tester, json);
        expect(find.text(label), findsOneWidget);
        expect(find.byType(Opacity), findsOneWidget);
        expect(
          find.descendant(of: find.byType(Opacity), matching: find.text(label)),
          findsNothing,
          reason: 'the ribbon stays at full strength',
        );
      }
    });

    testWidgets('an unlisted label replaces any ribbon', (tester) async {
      await pumpCard(
        tester,
        _listing(stock: 2, endsInHours: -1),
        showBadges: true,
      );

      expect(find.text('Unlisted - Pickup Ended'), findsOneWidget);
      expect(find.text('Only 2 left!'), findsNothing);
    });

    testWidgets('only customers see the saving, and nobody sees a halal tag', (
      tester,
    ) async {
      await pumpCard(tester, _listing());
      expect(find.text('Save 44%'), findsNothing);
      expect(find.text('Halal'), findsNothing);

      await pumpCard(tester, _listing(), showBadges: true);
      expect(find.text('Save 44%'), findsOneWidget);
      expect(find.text('Halal'), findsNothing);
    });

    testWidgets('non-halal listings show a pill unless unlisted', (
      tester,
    ) async {
      final nonHalal = {..._listing(), 'isHalal': false};

      for (final showBadges in [false, true]) {
        await pumpCard(tester, nonHalal, showBadges: showBadges);
        expect(find.text('Non-Halal'), findsOneWidget);
      }

      await pumpCard(tester, _listing());
      expect(find.text('Non-Halal'), findsNothing);

      await pumpCard(tester, {...nonHalal, 'quantityAvailable': 0});
      expect(find.text('Non-Halal'), findsNothing);
    });

    testWidgets('the ribbon and the Non-Halal pill line up', (tester) async {
      await pumpCard(tester, {
        ..._listing(createdAt: _inHours(0)),
        'isHalal': false,
      }, showBadges: true);

      Rect boxAround(String text) => tester.getRect(
        find
            .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
            .first,
      );

      expect(boxAround('Non-Halal').top, boxAround('New').top);
      expect(boxAround('Non-Halal').height, boxAround('New').height);
    });

    testWidgets('the New ribbon has a white fill', (tester) async {
      await pumpCard(
        tester,
        _listing(createdAt: _inHours(0)),
        showBadges: true,
      );

      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text('New'), matching: find.byType(DecoratedBox))
            .first,
      );
      expect((box.decoration as BoxDecoration).color, const Color(0xFFFFFFFF));
    });

    testWidgets('image areas match with or without a low-stock ribbon', (
      tester,
    ) async {
      double imageHeight() => tester
          .getSize(
            find.descendant(
              of: find.byType(ListingCard),
              matching: find.byType(Stack),
            ),
          )
          .height;

      await pumpCard(tester, _listing(stock: 5), showBadges: true);
      final lowStock = imageHeight();

      await pumpCard(tester, _listing(stock: 6), showBadges: true);
      expect(imageHeight(), lowStock);
    });

    testWidgets('a card cannot be tapped yet', (tester) async {
      await pumpCard(tester, _listing());

      expect(
        find.descendant(
          of: find.byType(ListingCard),
          matching: find.byType(InkWell),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ListingCard),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });

  group('badges', () {
    final now = DateTime(2026, 11, 6, 12);

    Listing make({
      int stock = 10,
      Duration closesIn = const Duration(hours: 3),
      Duration? addedAgo,
    }) => Listing(
      id: 'l1',
      title: 'Nasi',
      originalPrice: 8,
      discountedPrice: 4,
      quantityAvailable: stock,
      pickupStart: now,
      pickupEnd: now.add(closesIn),
      allergens: const [],
      otherAllergens: const [],
      status: 'active',
      createdAt: addedAgo == null ? null : now.subtract(addedAgo),
    );

    test('low stock comes first', () {
      final listing = make(
        stock: 5,
        closesIn: const Duration(minutes: 30),
        addedAgo: Duration.zero,
      );
      expect(listing.badgeAt(now), ListingBadge.lowStock);
    });

    test('ending soon comes next, up to one hour before closing', () {
      expect(
        make(
          closesIn: const Duration(hours: 1),
          addedAgo: Duration.zero,
        ).badgeAt(now),
        ListingBadge.endingSoon,
      );
      expect(make(closesIn: const Duration(minutes: 61)).badgeAt(now), isNull);
    });

    test('new lasts for one hour after adding', () {
      expect(
        make(addedAgo: const Duration(hours: 1)).badgeAt(now),
        ListingBadge.isNew,
      );
      expect(make(addedAgo: const Duration(minutes: 61)).badgeAt(now), isNull);
    });

    test('unavailable listings get no badge', () {
      expect(make(stock: 0).badgeAt(now), isNull);
      expect(make(closesIn: Duration.zero).badgeAt(now), isNull);
    });
  });

  test('the server response is parsed with the stall name', () async {
    final repository = ListingRepository(
      ApiClient(
        client: MockClient(
          (_) async => http.Response('{"listings":[],"hasMore":true}', 200),
        ),
      ),
    );

    final page = await repository.fetchAvailable(page: 2);
    expect(page.hasMore, isTrue);
    expect(Listing.fromJson(_listing()).stallName, 'Warung Pak Din');
  });
}
