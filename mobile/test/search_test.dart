import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/auth/presentation/providers/auth_provider.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/data/recent_searches.dart';
import 'package:savespoon/features/listings/presentation/pages/search_page.dart';
import 'package:savespoon/features/listings/presentation/providers/listing_changes.dart';
import 'package:savespoon/features/listings/presentation/widgets/category_picker.dart';
import 'package:savespoon/features/listings/presentation/widgets/search_result_row.dart';

import 'helpers.dart';

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Map<String, dynamic> _listing({
  String id = 'l1',
  String title = 'Nasi Lemak',
  int stock = 10,
  int endsInHours = 3,
  bool isHalal = true,
}) => {
  '_id': id,
  'title': title,
  'category': 'Rice',
  'isHalal': isHalal,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': stock,
  'pickupStart': _inHours(endsInHours - 2),
  'pickupEnd': _inHours(endsInHours),
  'allergens': const <String>[],
  'otherAllergens': const <String>[],
  'status': 'active',
  'stallName': 'Warung Pak Din',
  'pickupAddress': 'Arked Meranti, UTM Skudai',
};

class _MemoryStore implements RecentSearchStore {
  _MemoryStore([List<String> saved = const []]) : saved = [...saved];

  List<String> saved;
  String? account;

  @override
  Future<List<String>> read(String accountId) async {
    account = accountId;
    return saved;
  }

  @override
  Future<void> write(String accountId, List<String> searches) async {
    account = accountId;
    saved = searches;
  }
}

class _Server {
  _Server({
    this.results = const [],
    this.otherStalls = const [],
    this.runningOut = const [],
  });

  List<Map<String, dynamic>> results;
  List<Map<String, dynamic>> otherStalls;
  List<Map<String, dynamic>> runningOut;
  bool fail = false;
  Completer<void>? hold;
  bool hasMore = false;
  final List<Uri> searches = [];

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.endsWith('/running-out')) {
      return jsonResponse({'listings': runningOut});
    }
    searches.add(request.url);
    await hold?.future;
    if (fail) return jsonResponse({'error': 'Server is down'}, 500);
    final page = request.url.queryParameters['page'];
    return jsonResponse({
      'listings': page == '1'
          ? results
          : [_listing(id: 'next', title: 'Page two item')],
      'hasMore': page == '1' && hasMore,
      if (page == '1') 'otherStalls': otherStalls,
    });
  }
}

Future<GoRouter> _pump(
  WidgetTester tester,
  _Server server, {
  _MemoryStore? store,
  Size size = const Size(800, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            Scaffold(body: SearchPage(store: store ?? _MemoryStore())),
      ),
      GoRoute(
        path: '/customer/food/:id',
        builder: (context, state) =>
            Scaffold(body: Text('Details ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        Provider<ListingRepository>(
          create: (_) =>
              ListingRepository(ApiClient(client: MockClient(server.handle))),
        ),
        ChangeNotifierProvider<ListingChanges>(create: (_) => ListingChanges()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder get _box => find.byKey(const ValueKey('search-box'));

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_box, text);
  await tester.pump(SearchPage.typingPause);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the start screen shows categories, then recent searches', (
    tester,
  ) async {
    final server = _Server(
      runningOut: [_listing(id: 'r', title: 'Strip item', stock: 2)],
    );
    await _pump(tester, server, store: _MemoryStore(['nasi']));

    expect(find.text('Search for Surplus Food'), findsOneWidget);
    expect(find.text('Find meals by item, vendor or category'), findsOneWidget);
    expect(find.text('Search by food or vendor'), findsOneWidget);
    expect(find.text('Browse by Category'), findsOneWidget);
    expect(find.text('Recent Searches'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Browse by Category')).dy,
      lessThan(tester.getTopLeft(find.text('Recent Searches')).dy),
    );
    expect(find.text('Running Out Soon'), findsNothing);
    expect(find.text('Strip item'), findsNothing);
    expect(server.searches, isEmpty);
  });

  testWidgets('categories sit in one row that scrolls sideways', (
    tester,
  ) async {
    await _pump(tester, _Server(), size: const Size(400, 1600));

    final rice = tester.getTopLeft(find.byKey(const ValueKey('category-Rice')));
    final drinks = find.byKey(const ValueKey('category-Drinks'));
    expect(tester.getTopLeft(drinks).dy, rice.dy);

    final list = find.ancestor(
      of: find.byKey(const ValueKey('category-Rice')),
      matching: find.byType(ListView),
    );
    expect(tester.widget<ListView>(list).scrollDirection, Axis.horizontal);
    final circle = tester.widget<Container>(
      find
          .ancestor(
            of: find.descendant(
              of: find.byKey(const ValueKey('category-Rice')),
              matching: find.byIcon(categoryIcon('Rice')),
            ),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = circle.decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, AppColors.primaryPale);
    expect(find.text('Recent Searches'), findsNothing);
  });

  testWidgets('a category searches that word without saving it', (
    tester,
  ) async {
    final server = _Server(results: [_listing()]);
    final store = _MemoryStore();
    await _pump(tester, server, store: store);

    await tester.tap(find.byKey(const ValueKey('category-Rice')));
    await tester.pumpAndSettle();

    expect(server.searches.single.queryParameters['q'], 'Rice');
    expect(find.byType(SearchResultRow), findsOneWidget);
    expect(store.saved, isEmpty);
  });

  testWidgets('typing searches after the pause and shows rows', (tester) async {
    final server = _Server(results: [_listing(title: 'Nasi Lemak')]);
    await _pump(tester, server);

    await tester.enterText(_box, 'nas');
    await tester.pump(SearchPage.typingPause - const Duration(milliseconds: 1));
    expect(server.searches, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(server.searches.single.queryParameters, {'q': 'nas', 'page': '1'});
    expect(find.byType(SearchResultRow), findsOneWidget);
    expect(find.text('From Warung Pak Din'), findsOneWidget);
    expect(find.text('Save 44%'), findsOneWidget);
    expect(find.text('Arked Meranti, UTM Skudai'), findsOneWidget);
    expect(find.text('Best Match'), findsOneWidget);
    expect(find.text('Browse by Category'), findsNothing);
  });

  testWidgets('the ribbon sits on the image, which runs the full height', (
    tester,
  ) async {
    await _pump(tester, _Server(results: [_listing(stock: 2)]));
    await _type(tester, 'nasi');

    final image = tester.getRect(
      find
          .ancestor(
            of: find.descendant(
              of: find.byType(SearchResultRow),
              matching: find.byIcon(categoryIcon('Rice')),
            ),
            matching: find.byType(ClipRRect),
          )
          .first,
    );
    final ribbon = tester.getRect(find.text('Only 2 left!'));
    expect(image.inflate(0.5).contains(ribbon.topLeft), isTrue);
    expect(image.inflate(0.5).contains(ribbon.bottomRight), isTrue);
    expect(
      image.bottom,
      greaterThanOrEqualTo(
        tester.getRect(find.text('Arked Meranti, UTM Skudai')).bottom,
      ),
    );
  });

  testWidgets('the text sits in the middle of the row', (tester) async {
    await _pump(
      tester,
      _Server(
        results: [
          {..._listing(id: 'a', title: 'Teh'), 'pickupAddress': null},
        ],
      ),
    );
    await _type(tester, 'teh');

    final row = tester.getRect(find.byKey(const ValueKey('search-result-a')));
    final stall = tester.getRect(find.text('From Warung Pak Din'));
    final pickup = tester.getRect(find.textContaining(' - '));
    final middle = (stall.top + pickup.bottom) / 2;
    expect(middle, closeTo(row.center.dy, 1.5));
  });

  testWidgets('Non-Halal sits beside a short name and under a long one', (
    tester,
  ) async {
    const longName = 'Nasi Lemak Ayam Goreng Berempah Special';
    await _pump(
      tester,
      _Server(
        results: [
          _listing(id: 'a', title: 'Teh', isHalal: false),
          _listing(id: 'b', title: longName, isHalal: false),
        ],
      ),
    );
    await _type(tester, 'a');

    Finder inRow(String id, Finder finder) => find.descendant(
      of: find.byKey(ValueKey('search-result-$id')),
      matching: finder,
    );
    final short = tester.getRect(inRow('a', find.text('Teh')));
    final shortTag = tester.getRect(inRow('a', find.text('Non-Halal')));
    expect(shortTag.left, greaterThan(short.right));
    expect(shortTag.center.dy, closeTo(short.center.dy, 4));

    final long = tester.getRect(inRow('b', find.text(longName)));
    final longTag = tester.getRect(
      inRow('b', find.byKey(const ValueKey('non-halal'))),
    );
    expect(longTag.top, greaterThanOrEqualTo(long.bottom));
    expect(longTag.left, closeTo(long.left, 1));

    final tag = tester.widget<DecoratedBox>(
      find.descendant(
        of: inRow('a', find.byKey(const ValueKey('non-halal'))),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((tag.decoration as BoxDecoration).color, AppColors.field);
    expect(
      find.descendant(
        of: find.byType(ClipRRect),
        matching: find.text('Non-Halal'),
      ),
      findsNothing,
      reason: 'not on the image',
    );
  });

  testWidgets('every row is the same size on a narrow phone', (tester) async {
    await _pump(
      tester,
      _Server(
        results: [
          {..._listing(id: 'a', title: 'Teh'), 'pickupAddress': null},
          _listing(
            id: 'b',
            title: 'Nasi Lemak Ayam Goreng Berempah Special With Extra Sambal',
            stock: 2,
            isHalal: false,
          ),
          _listing(id: 'c', title: 'Kuey Teow Goreng'),
        ],
      ),
      size: const Size(360, 1600),
    );
    await _type(tester, 'a');

    final sizes = [
      for (final id in ['a', 'b', 'c'])
        tester.getSize(find.byKey(ValueKey('search-result-$id'))),
    ];
    expect(sizes.toSet().length, 1, reason: '$sizes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save shows as a filled pill', (tester) async {
    await _pump(tester, _Server(results: [_listing()]));
    await _type(tester, 'nasi');

    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.text('Save 44%'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, AppColors.warningPale);
  });

  testWidgets('earlier results stay while the next search loads', (
    tester,
  ) async {
    final server = _Server(results: [_listing(title: 'First')]);
    await _pump(tester, server);
    await _type(tester, 'fir');

    server
      ..results = [_listing(title: 'Second')]
      ..hold = Completer<void>();
    await tester.enterText(_box, 'sec');
    await tester.pump(SearchPage.typingPause);
    await tester.pump();

    expect(find.text('First'), findsOneWidget);
    expect(
      find.descendant(
        of: _box,
        matching: find.byKey(const ValueKey('search-progress')),
      ),
      findsOneWidget,
      reason: 'the spinner sits inside the search field',
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    server.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(find.byKey(const ValueKey('search-progress')), findsNothing);
  });

  testWidgets('quick typing sends one search for the last text', (
    tester,
  ) async {
    final server = _Server(results: [_listing()]);
    await _pump(tester, server);

    await tester.enterText(_box, 'n');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(_box, 'na');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(_box, 'nasi   lemak ');
    await tester.pump(SearchPage.typingPause);
    await tester.pumpAndSettle();

    expect(server.searches.length, 1);
    expect(server.searches.single.queryParameters['q'], 'nasi lemak');
  });

  testWidgets('the keyboard Search key searches at once and saves it', (
    tester,
  ) async {
    final server = _Server(results: [_listing()]);
    final store = _MemoryStore();
    await _pump(tester, server, store: store);

    await tester.enterText(_box, 'ayam');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(server.searches.length, 1);
    expect(store.saved, ['ayam']);
  });

  testWidgets('typing alone does not save a recent search', (tester) async {
    final store = _MemoryStore();
    await _pump(tester, _Server(results: [_listing()]), store: store);

    await _type(tester, 'na');

    expect(store.saved, isEmpty);
  });

  testWidgets('recent searches can be run and removed', (tester) async {
    final server = _Server(results: [_listing()]);
    final store = _MemoryStore(['nasi', 'teh']);
    await _pump(tester, server, store: store);

    expect(find.text('Recent Searches'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('recent-teh')),
        matching: find.byIcon(Icons.history),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('teh'));
    await tester.pumpAndSettle();
    expect(server.searches.single.queryParameters['q'], 'teh');
    expect(store.saved, ['teh', 'nasi']);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('recent-nasi')),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.saved, ['teh']);
    expect(find.text('nasi'), findsNothing);
  });

  testWidgets('Clear All removes every recent search', (tester) async {
    final store = _MemoryStore(['nasi', 'teh']);
    await _pump(tester, _Server(), store: store);

    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();

    expect(store.saved, isEmpty);
    expect(find.text('Recent Searches'), findsNothing);
  });

  testWidgets('clearing the box returns to the start screen', (tester) async {
    await _pump(tester, _Server(results: [_listing()]));
    await _type(tester, 'nasi');
    expect(find.text('Browse by Category'), findsNothing);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchResultRow), findsNothing);
    expect(find.text('Browse by Category'), findsOneWidget);
    expect(find.byTooltip('Clear'), findsNothing);
  });

  testWidgets('no results says so', (tester) async {
    await _pump(tester, _Server());
    await _type(tester, 'zzz');

    expect(find.text("No results for 'zzz'"), findsOneWidget);
    expect(find.text('Other Vendors You Might Like'), findsNothing);
  });

  testWidgets('closed or sold-out results are never shown', (tester) async {
    await _pump(
      tester,
      _Server(
        results: [
          _listing(id: 'a', title: 'Open'),
          _listing(id: 'b', title: 'Closed', endsInHours: -1),
          _listing(id: 'c', title: 'Empty', stock: 0),
        ],
      ),
    );
    await _type(tester, 'a');

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
    expect(find.text('Empty'), findsNothing);
  });

  testWidgets('an error offers Try again', (tester) async {
    final server = _Server(results: [_listing()])..fail = true;
    await _pump(tester, server);
    await _type(tester, 'nasi');
    expect(find.text('Server is down'), findsOneWidget);

    server.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Server is down'), findsNothing);
    expect(find.byType(SearchResultRow), findsOneWidget);
  });

  testWidgets('other stalls show under the results', (tester) async {
    await _pump(
      tester,
      _Server(
        results: [_listing(title: 'Nasi Campur Set')],
        otherStalls: [_listing(id: 'o', title: 'Nasi Goreng Kampung')],
      ),
    );
    await _type(tester, 'pak din');

    expect(find.text('Other Vendors You Might Like'), findsOneWidget);
    expect(find.text('Nasi Goreng Kampung'), findsOneWidget);
    expect(find.byType(SearchResultRow), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Nasi Campur Set')).dy,
      lessThan(tester.getTopLeft(find.text('Other Vendors You Might Like')).dy),
    );
  });

  testWidgets('tapping a row opens the details page', (tester) async {
    final store = _MemoryStore();
    await _pump(
      tester,
      _Server(results: [_listing(id: 'abc')]),
      store: store,
    );
    await _type(tester, 'nasi');

    await tester.tap(find.byKey(const ValueKey('search-result-abc')));
    await tester.pumpAndSettle();

    expect(find.text('Details abc'), findsOneWidget);
    expect(store.saved, ['nasi']);
  });

  testWidgets('coming back from details refreshes the results', (tester) async {
    final server = _Server(
      results: [_listing(id: 'abc', title: 'Old')],
    );
    final router = await _pump(tester, server);
    await _type(tester, 'nasi');

    await tester.tap(find.byKey(const ValueKey('search-result-abc')));
    await tester.pumpAndSettle();
    server.results = [
      _listing(id: 'abc', title: 'Old'),
      _listing(id: 'new', title: 'Just added'),
    ];
    router.pop();
    await tester.pumpAndSettle();

    expect(server.searches.length, 2);
    expect(find.text('Just added'), findsOneWidget);
  });

  testWidgets('pull to refresh searches again', (tester) async {
    final server = _Server(results: [_listing(title: 'Before')]);
    await _pump(tester, server);
    await _type(tester, 'b');

    server.results = [_listing(title: 'After')];
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 500),
      1000,
    );
    await tester.pumpAndSettle();

    expect(find.text('After'), findsOneWidget);
    expect(server.searches.length, 2);
  });

  testWidgets('more results load on scroll', (tester) async {
    final server = _Server(
      results: [
        for (var i = 0; i < 20; i++) _listing(id: 'p$i', title: 'Item $i'),
      ],
    )..hasMore = true;
    await _pump(tester, server, size: const Size(800, 800));
    await _type(tester, 'item');

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(server.searches.last.queryParameters['page'], '2');
    expect(find.text('Page two item'), findsOneWidget);
  });

  testWidgets('the box stops at 50 characters', (tester) async {
    await _pump(tester, _Server());
    await tester.enterText(_box, 'a' * 60);

    expect(tester.widget<TextField>(_box).controller!.text.length, 50);
  });

  test('recent searches keep the newest 6 without repeats', () {
    var recent = <String>[];
    for (final term in ['a', 'b', 'c', 'd', 'e', 'f', 'g']) {
      recent = withRecentSearch(recent, term);
    }
    expect(recent, ['g', 'f', 'e', 'd', 'c', 'b']);
    expect(withRecentSearch(recent, '  C  '), ['C', 'g', 'f', 'e', 'd', 'b']);
    expect(withRecentSearch(recent, '   '), recent);
  });

  test('the repository sends the keyword safely', () async {
    late Uri sent;
    final repository = ListingRepository(
      ApiClient(
        client: MockClient((request) async {
          sent = request.url;
          return jsonResponse({'listings': [], 'hasMore': false});
        }),
      ),
    );

    final found = await repository.search('teh c & ais', page: 2);

    expect(sent.path, '/api/listings/search');
    expect(sent.queryParameters, {'q': 'teh c & ais', 'page': '2'});
    expect(found.otherStalls, isEmpty);
  });
}
