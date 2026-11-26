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
import 'package:savespoon/features/listings/data/saved_filters.dart';
import 'package:savespoon/features/listings/domain/search_filters.dart';
import 'package:savespoon/features/listings/presentation/pages/search_page.dart';
import 'package:savespoon/features/listings/presentation/providers/listing_changes.dart';
import 'package:savespoon/features/listings/presentation/providers/search_shortcut.dart';
import 'package:savespoon/features/listings/presentation/widgets/active_filter_chips.dart';
import 'package:savespoon/features/listings/presentation/widgets/filter_sheet.dart';
import 'package:savespoon/features/listings/presentation/widgets/search_result_row.dart';

import 'helpers.dart';

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
  'pickupStart': _inHours(-1),
  'pickupEnd': _inHours(3),
  'allergens': const <String>[],
  'otherAllergens': const <String>[],
  'status': 'active',
  'stallName': 'Warung Pak Din',
};

class _Recent implements RecentSearchStore {
  List<String> saved = [];

  @override
  Future<List<String>> read(String accountId) async => saved;

  @override
  Future<void> write(String accountId, List<String> searches) async =>
      saved = searches;
}

class _Filters implements SearchFilterStore {
  _Filters([this.saved = SearchFilters.none]);

  SearchFilters saved;
  int writes = 0;
  // Holds the read back, like a slow phone on a cold start.
  Completer<void>? wait;

  @override
  Future<SearchFilters> read(String accountId) async {
    await wait?.future;
    return saved;
  }

  @override
  Future<void> write(String accountId, SearchFilters filters) async {
    writes++;
    saved = filters;
  }
}

class _Server {
  List<Map<String, dynamic>> results = [_listing()];
  bool hasMore = false;
  final List<Uri> searches = [];

  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/api/favourites/ids') {
      return jsonResponse({'listingIds': []});
    }
    searches.add(request.url);
    final firstPage = request.url.queryParameters['page'] == '1';
    return jsonResponse({
      'listings': firstPage ? results : [_listing(id: 'next', title: 'Next')],
      'hasMore': firstPage && hasMore,
      'otherStalls': [],
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Server server, {
  _Filters? filters,
  _Recent? recent,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/customer/search',
    routes: [
      GoRoute(
        path: '/customer/search',
        builder: (context, state) => Scaffold(
          body: SearchPage(
            store: recent ?? _Recent(),
            filterStore: filters ?? _Filters(),
          ),
        ),
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
        favouritesProvider(server.handle),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String key) => find.byKey(ValueKey(key));

FilledButton _apply(WidgetTester tester) =>
    tester.widget<FilledButton>(_key('filter-apply'));

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(_key('filter-button'));
  await tester.pumpAndSettle();
}

Future<void> _tapInSheet(WidgetTester tester, String key) async {
  await tester.ensureVisible(_key(key));
  await tester.pumpAndSettle();
  await tester.tap(_key(key));
  await tester.pumpAndSettle();
}

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

void main() {
  group('the filters themselves', () {
    test('count one per chip, and ignore the order of choices', () {
      const a = SearchFilters(
        categories: {'Rice', 'Drinks'},
        avoid: {'egg'},
        halalOnly: true,
        sort: SearchSort.mostSold,
      );
      const b = SearchFilters(
        categories: {'Drinks', 'Rice'},
        avoid: {'egg'},
        halalOnly: true,
        sort: SearchSort.mostSold,
      );
      expect(a.activeCount, 5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(sort: null), isFalse);
      expect(SearchFilters.none.isEmpty, isTrue);
    });

    test('last per account only while the app is open', () async {
      const store = SessionSearchFilterStore();
      const filters = SearchFilters(halalOnly: true);
      await store.write('a', filters);

      expect(await store.read('a'), filters);
      expect(await store.read('b'), SearchFilters.none);
      await store.write('a', SearchFilters.none);
      expect(await store.read('a'), SearchFilters.none);
    });

    test('Best Match falls back without a keyword', () {
      const filters = SearchFilters(sort: SearchSort.bestMatch);
      expect(filters.forKeyword(hasKeyword: false).sort, isNull);
      expect(
        filters.forKeyword(hasKeyword: false).sortFor(hasKeyword: false),
        SearchSort.newest,
      );
      expect(filters.forKeyword(hasKeyword: true), filters);
    });
  });

  testWidgets('Apply stays off until something changes, and back again', (
    tester,
  ) async {
    await _pump(tester, _Server());
    await _openSheet(tester);

    expect(find.text('Filter and Sort'), findsOneWidget);
    expect(_apply(tester).onPressed, isNull);

    await _tapInSheet(tester, 'filter-halal');
    expect(_apply(tester).onPressed, isNotNull);

    await _tapInSheet(tester, 'filter-halal');
    expect(_apply(tester).onPressed, isNull);
  });

  testWidgets('applying filters lists matching food with chips and a count', (
    tester,
  ) async {
    final server = _Server();
    final saved = _Filters();
    await _pump(tester, server, filters: saved);
    await _openSheet(tester);

    expect(find.text(allergenNote), findsOneWidget);
    await _tapInSheet(tester, 'filter-category-Noodles');
    await _tapInSheet(tester, 'filter-category-Rice');
    await _tapInSheet(tester, 'filter-avoid-egg');
    await _tapInSheet(tester, 'filter-apply');

    expect(server.searches.last.queryParameters, {
      'category': 'Rice,Noodles',
      'avoid': 'egg',
      'page': '1',
    });
    expect(find.byType(SearchResultRow), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(_key('active-filter-category-Rice'), findsOneWidget);
    expect(_key('active-filter-avoid-egg'), findsOneWidget);
    expect(find.text('Avoid Egg'), findsOneWidget);
    expect(
      find.descendant(of: _key('filter-button'), matching: find.text('3')),
      findsOneWidget,
    );
    expect(saved.saved.categories, {'Rice', 'Noodles'});
  });

  testWidgets(
    'removing a chip searches again, and the last one goes back to the start',
    (tester) async {
      final server = _Server();
      await _pump(
        tester,
        server,
        filters: _Filters(const SearchFilters(halalOnly: true)),
      );

      // Saved filters show their results straight away, not the start screen.
      expect(find.text('Browse by Category'), findsNothing);
      expect(find.text('Halal Only'), findsOneWidget);
      expect(find.byType(SearchResultRow), findsOneWidget);
      expect(server.searches.last.queryParameters, {'halal': '1', 'page': '1'});

      await _openSheet(tester);
      await _tapInSheet(tester, 'filter-category-Rice');
      await tester.tap(_key('filter-apply'));
      await tester.pumpAndSettle();
      expect(server.searches.last.queryParameters, {
        'category': 'Rice',
        'halal': '1',
        'page': '1',
      });

      await tester.tap(
        find.descendant(
          of: _key('active-filter-halal'),
          matching: find.byTooltip('Remove'),
        ),
      );
      await tester.pumpAndSettle();
      expect(server.searches.last.queryParameters, {
        'category': 'Rice',
        'page': '1',
      });

      await tester.tap(
        find.descendant(
          of: _key('active-filter-category-Rice'),
          matching: find.byTooltip('Remove'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Browse by Category'), findsOneWidget);
      expect(find.byType(SearchResultRow), findsNothing);
    },
  );

  testWidgets(
    'a keyword and filters go together, and Best Match only shows with a keyword',
    (tester) async {
      final server = _Server();
      await _pump(tester, server);

      await _openSheet(tester);
      expect(_key('sort-best'), findsNothing);
      expect(tester.widget<ChoiceChip>(_key('sort-newest')).selected, isTrue);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('search-box')), 'nasi');
      await tester.pump(SearchPage.typingPause);
      await tester.pumpAndSettle();
      await _openSheet(tester);
      expect(tester.widget<ChoiceChip>(_key('sort-best')).selected, isTrue);
      await _tapInSheet(tester, 'sort-price_asc');
      await _tapInSheet(tester, 'filter-favourites');
      await _tapInSheet(tester, 'filter-apply');

      expect(server.searches.last.queryParameters, {
        'q': 'nasi',
        'favourites': '1',
        'sort': 'price_asc',
        'page': '1',
      });
      expect(find.text('Price: Low to High'), findsNWidgets(2));
    },
  );

  testWidgets('the max price slider and Reset', (tester) async {
    final server = _Server();
    await _pump(tester, server);
    await _openSheet(tester);

    expect(find.text('Max Price: Any Price'), findsOneWidget);
    tester.widget<Slider>(_key('filter-max-price')).onChanged!(5);
    await tester.pumpAndSettle();
    expect(find.text('Max Price: Up to RM 5.00'), findsOneWidget);

    await _tapInSheet(tester, 'filter-reset');
    expect(find.text('Max Price: Any Price'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(_key('filter-reset')).onPressed,
      isNull,
    );
  });

  testWidgets('filters with no matches say so', (tester) async {
    final server = _Server()..results = [];
    await _pump(tester, server);
    await _openSheet(tester);
    await _tapInSheet(tester, 'filter-open-now');
    await _tapInSheet(tester, 'filter-apply');

    expect(find.text('No food matches your filters'), findsOneWidget);
    expect(find.text('Try removing a filter.'), findsOneWidget);
  });

  testWidgets('more filtered results load on scroll with the same filters', (
    tester,
  ) async {
    final server = _Server()
      ..hasMore = true
      ..results = [
        for (var index = 0; index < 20; index++)
          _listing(id: 'l$index', title: 'Item $index'),
      ];
    await _pump(tester, server);
    await tester.tap(_key('category-Drinks'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(server.searches.last.queryParameters, {
      'category': 'Drinks',
      'page': '2',
    });
  });

  testWidgets('the filter sheet never overflows', (tester) async {
    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: _AndroidText(scale)),
              child: child!,
            ),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: FilterSheet(
                  current: SearchFilters(
                    categories: {'Rice', 'Desserts'},
                    avoid: {'shellfish', 'belacan'},
                    maxPrice: 12,
                    sort: SearchSort.biggestSaving,
                  ),
                  hasKeyword: true,
                ),
              ),
            ),
          ),
        );
        final error = tester.takeException();
        if (error != null) fail('width $width, text x$scale: $error');
      }
    }
    tester.view.reset();
  });

  testWidgets('the active filter chips never overflow', (tester) async {
    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: _AndroidText(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: ActiveFilterChips(
                  filters: const SearchFilters(
                    categories: {'Rice', 'Noodles', 'Desserts'},
                    avoid: {'shellfish', 'peanut'},
                    halalOnly: true,
                    maxPrice: 12,
                    favouritesOnly: true,
                    openNow: true,
                    sort: SearchSort.priceHighToLow,
                  ),
                  hasKeyword: false,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        final error = tester.takeException();
        if (error != null) fail('width $width, text x$scale: $error');
      }
    }
    tester.view.reset();
  });

  testWidgets('the sheet covers at most 60% of the screen and scrolls inside', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFilterSheet(
                context,
                current: SearchFilters.none,
                hasKeyword: true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(FilterSheet)).height,
      lessThanOrEqualTo(640 * FilterSheet.maxShare),
    );
    expect(find.byKey(const ValueKey('filter-apply')).hitTestable(), findsOne);
    expect(find.byKey(const ValueKey('filter-reset')).hitTestable(), findsOne);
  });

  testWidgets(
    'the chips stay on one line that scrolls sideways, fading at the edge',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SearchFilters? changed;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ActiveFilterChips(
              filters: const SearchFilters(
                categories: {'Rice', 'Noodles', 'Desserts'},
                avoid: {'shellfish', 'peanut'},
                halalOnly: true,
                openNow: true,
              ),
              hasKeyword: false,
              onChanged: (next) => changed = next,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tops = {
        for (final element in find.byType(InputChip).evaluate())
          tester.getTopLeft(find.byWidget(element.widget)).dy,
      };
      expect(tops, hasLength(1));
      expect(find.byType(ShaderMask), findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scroll.scrollDirection, Axis.horizontal);

      await tester.dragUntilVisible(
        find.byKey(const ValueKey('active-filter-clear-all')),
        find.byType(SingleChildScrollView),
        const Offset(-200, 0),
      );
      await tester.tap(find.byKey(const ValueKey('active-filter-clear-all')));
      await tester.pumpAndSettle();
      expect(changed, SearchFilters.none);
    },
  );

  testWidgets('new results fade in, and a quiet refresh does not replay it', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    await tester.tap(_key('category-Rice'));
    await tester.pump();
    await tester.pump();

    final fade = find.ancestor(
      of: find.byType(SearchResultRow),
      matching: find.byType(FadeTransition),
    );
    expect(
      tester.widget<FadeTransition>(fade.first).opacity.value,
      lessThan(1),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 1);

    await tester.pump(const Duration(seconds: 31));
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade.first).opacity.value, 1);
  });

  testWidgets('Clear All fades the recent searches out, then removes them', (
    tester,
  ) async {
    final recent = _Recent()..saved = ['nasi', 'teh'];
    await _pump(tester, _Server(), recent: recent);
    expect(find.text('Recent Searches'), findsOneWidget);

    await tester.tap(find.text('Clear All'));
    await tester.pump();
    expect(find.text('Recent Searches'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Recent Searches'), findsNothing);
    expect(recent.saved, isEmpty);
  });

  testWidgets('removing one recent search fades it out first', (tester) async {
    final recent = _Recent()..saved = ['nasi', 'teh'];
    await _pump(tester, _Server(), recent: recent);

    await tester.tap(
      find.descendant(
        of: _key('recent-nasi'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pump();
    expect(_key('recent-nasi'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(_key('recent-nasi'), findsNothing);
    expect(recent.saved, ['teh']);
  });

  testWidgets('a shortcut from elsewhere opens Search on just those filters', (
    tester,
  ) async {
    final server = _Server();
    await _pump(
      tester,
      server,
      filters: _Filters(const SearchFilters(halalOnly: true)),
    );
    await tester.enterText(find.byType(TextField), 'nasi');
    await tester.pumpAndSettle();

    SearchShortcut.open(
      tester.element(find.byType(SearchPage)),
      const SearchFilters(favouritesOnly: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(SafeArea),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, lessThan(1));
    await tester.pumpAndSettle();
    expect(fade.opacity.value, 1);

    expect(find.text('nasi'), findsNothing);
    expect(_key('active-filter-favourites'), findsOneWidget);
    expect(_key('active-filter-halal'), findsNothing);
    expect(server.searches.last.queryParameters, {
      'favourites': '1',
      'page': '1',
    });
    expect(find.byType(SearchResultRow), findsOneWidget);
  });

  testWidgets('category tiles grow with the text and never overflow', (
    tester,
  ) async {
    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
            Provider<ListingRepository>(
              create: (_) => ListingRepository(
                ApiClient(client: MockClient(_Server().handle)),
              ),
            ),
            ChangeNotifierProvider<ListingChanges>(
              create: (_) => ListingChanges(),
            ),
            favouritesProvider(_Server().handle),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: _AndroidText(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SearchPage(store: _Recent(), filterStore: _Filters()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final error = tester.takeException();
      if (error != null) fail('text x$scale: $error');
      final tile = tester.getSize(_key('category-Rice'));
      expect(
        tile.width,
        greaterThanOrEqualTo(84 * (_AndroidText(scale).scale(14) / 14) - 0.5),
        reason: 'text x$scale',
      );
    }
    tester.view.reset();
  });

  testWidgets('saved filters open on their results, never flashing the start', (
    tester,
  ) async {
    final filters = _Filters(const SearchFilters(halalOnly: true))
      ..wait = Completer<void>();
    final server = _Server();
    await _pump(tester, server, filters: filters);

    final start = find.byType(SliverFadeTransition, skipOffstage: false);
    expect(tester.widget<SliverFadeTransition>(start).opacity.value, 0);

    filters.wait!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Browse by Category'), findsNothing);
    expect(find.byType(SearchResultRow), findsOneWidget);
    expect(server.searches.last.queryParameters, {'halal': '1', 'page': '1'});
  });

  testWidgets('with nothing saved, the start screen fades in once loaded', (
    tester,
  ) async {
    final filters = _Filters()..wait = Completer<void>();
    await _pump(tester, _Server(), filters: filters);
    final start = find.byType(SliverFadeTransition, skipOffstage: false);
    expect(tester.widget<SliverFadeTransition>(start).opacity.value, 0);

    filters.wait!.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final halfway = tester.widget<SliverFadeTransition>(start).opacity.value;
    expect(halfway, greaterThan(0));
    expect(halfway, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<SliverFadeTransition>(start).opacity.value, 1);
  });

  testWidgets('a removed chip fades and closes up before the filter goes', (
    tester,
  ) async {
    final server = _Server();
    await _pump(
      tester,
      server,
      filters: _Filters(
        const SearchFilters(halalOnly: true, categories: {'Rice'}),
      ),
    );
    final searches = server.searches.length;

    await tester.tap(
      find.descendant(
        of: _key('active-filter-halal'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.searches.length, searches);
    final fading = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: _key('active-filter-space-halal'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(fading.opacity, 0);

    await tester.pumpAndSettle();
    expect(_key('active-filter-halal'), findsNothing);
    expect(server.searches.last.queryParameters, {
      'category': 'Rice',
      'page': '1',
    });
  });

  testWidgets('removing two chips quickly removes both', (tester) async {
    final server = _Server();
    await _pump(
      tester,
      server,
      filters: _Filters(
        const SearchFilters(
          halalOnly: true,
          openNow: true,
          categories: {'Rice'},
        ),
      ),
    );

    for (final key in ['halal', 'open-now']) {
      await tester.tap(
        find.descendant(
          of: _key('active-filter-$key'),
          matching: find.byTooltip('Remove'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(server.searches.last.queryParameters, {
      'category': 'Rice',
      'page': '1',
    });
  });
}
