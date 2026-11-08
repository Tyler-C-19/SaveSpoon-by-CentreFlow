import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/routing/app_router.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/domain/listing_validators.dart';
import 'package:savespoon/features/listings/domain/pickup_times.dart';
import 'package:savespoon/features/listings/presentation/pages/add_listing_page.dart';
import 'package:savespoon/features/listings/presentation/pages/vendor_listings_page.dart';
import 'package:savespoon/features/listings/presentation/widgets/allergen_picker.dart';
import 'package:savespoon/features/listings/presentation/widgets/category_picker.dart';

import 'helpers.dart';

final DateTime _now = DateTime(2026, 11, 6, 10);

Map<String, dynamic> _listingJson({
  String id = 'l1',
  String title = 'Nasi Lemak',
  List<String> allergens = const [],
  List<String> otherAllergens = const [],
}) => {
  '_id': id,
  'title': title,
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': 6,
  'pickupStart': DateTime(2026, 11, 6, 18).toUtc().toIso8601String(),
  'pickupEnd': DateTime(2026, 11, 6, 20).toUtc().toIso8601String(),
  'allergens': allergens,
  'otherAllergens': otherAllergens,
  'status': 'active',
};

Future<void> _pumpPages(
  WidgetTester tester,
  MockClientHandler onRequest, {
  List<TimeOfDay> times = const [
    TimeOfDay(hour: 18, minute: 0),
    TimeOfDay(hour: 20, minute: 0),
  ],
}) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  var nextTime = 0;
  final router = GoRouter(
    initialLocation: AppRoutes.vendorListings,
    routes: [
      GoRoute(
        path: AppRoutes.vendorListings,
        builder: (context, state) => const Scaffold(body: VendorListingsPage()),
      ),
      GoRoute(
        path: AppRoutes.vendorAddListing,
        builder: (context, state) => AddListingPage(
          now: () => _now,
          timePicker: (context, initial) async =>
              times[nextTime++ % times.length],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    Provider<ListingRepository>(
      create: (_) =>
          ListingRepository(ApiClient(client: MockClient(onRequest))),
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openForm(WidgetTester tester) async {
  await tester.tap(find.text('Add Listing'));
  await tester.pumpAndSettle();
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.bySemanticsLabel('Item name'), 'Nasi Lemak');
  await tester.enterText(find.bySemanticsLabel('Original (RM)'), '8');
  await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '4.50');
  await tester.enterText(find.bySemanticsLabel('Stock'), '6');
  await tester.tap(find.text('Rice'));
  await tester.tap(find.text('Yes'));
  await tester.tap(find.byIcon(Icons.schedule).first);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.schedule).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save Listing'));
  await tester.pumpAndSettle();
}

void main() {
  group('validators', () {
    test('title length', () {
      expect(ListingValidators.title('A'), isNotNull);
      expect(ListingValidators.title('A' * 81), isNotNull);
      expect(ListingValidators.title('Nasi'), isNull);
    });

    test('description is optional up to 500 characters', () {
      expect(ListingValidators.description(''), isNull);
      expect(ListingValidators.description('A' * 501), isNotNull);
    });

    test('prices are above 0 with up to 2 decimals', () {
      for (final bad in ['', '0', '0.00', '-1', '8.123', 'abc']) {
        expect(ListingValidators.originalPrice(bad), isNotNull, reason: bad);
      }
      for (final good in ['8', '8.5', '8.50']) {
        expect(ListingValidators.originalPrice(good), isNull, reason: good);
      }
    });

    test('discounted price is less than the original', () {
      expect(ListingValidators.discountedPrice('8', '8'), isNotNull);
      expect(ListingValidators.discountedPrice('9', '8'), isNotNull);
      expect(ListingValidators.discountedPrice('4.50', '8'), isNull);
    });

    test('stock is a whole number from 1 to 999', () {
      for (final bad in ['', '0', '1000', '1.5', 'abc']) {
        expect(ListingValidators.stock(bad), isNotNull, reason: bad);
      }
      expect(ListingValidators.stock('999'), isNull);
    });

    test(
      'pickup needs both times, ends after it starts and is in the future',
      () {
        DateTime at(int hour) => DateTime(2026, 11, 6, hour);
        expect(ListingValidators.pickup(null, at(12), _now), isNotNull);
        expect(ListingValidators.pickup(at(12), null, _now), isNotNull);
        expect(ListingValidators.pickup(at(12), at(12), _now), isNotNull);
        expect(ListingValidators.pickup(at(13), at(12), _now), isNotNull);
        expect(ListingValidators.pickup(at(8), at(9), _now), isNotNull);
        expect(ListingValidators.pickup(at(8), at(12), _now), isNull);
      },
    );
  });

  test('other allergens are checked and split on commas', () {
    expect(ListingValidators.otherAllergens(''), isNull);
    expect(ListingValidators.otherAllergens('mango, kiwi'), isNull);
    expect(ListingValidators.otherAllergens('a'), isNotNull);
    expect(ListingValidators.otherAllergens('<b>mango</b>'), isNotNull);
    expect(ListingValidators.otherAllergens('aa,bb,cc,dd,ee,ff'), isNotNull);
    expect(ListingValidators.splitOtherAllergens(' mango, ,kiwi '), [
      'mango',
      'kiwi',
    ]);
  });

  test('the allergen summary includes other allergens', () {
    expect(
      Listing.fromJson(
        _listingJson(allergens: ['egg'], otherAllergens: ['Mango']),
      ).allergenSummary,
      'Egg, Mango',
    );
  });

  test('allergens show as None declared when empty', () {
    expect(Listing.fromJson(_listingJson()).allergenSummary, 'None declared');
    expect(
      Listing.fromJson(_listingJson(allergens: ['egg', 'sesame']))
          .allergenSummary,
      'Egg, Sesame',
    );
  });

  testWidgets('other allergens help lines up with the field', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AllergenPicker(
              selected: const {},
              onToggled: (_) {},
              otherAllergens: controller,
              onSuggest: () {},
              isSuggesting: false,
              usedAi: false,
              confirmed: false,
              onConfirmed: (_) {},
            ),
          ),
        ),
      ),
    );

    final help = find.textContaining('Leave empty for "None declared"');
    expect(find.textContaining('chips'), findsNothing);
    expect(
      tester.getTopLeft(help).dx,
      tester.getTopLeft(find.byType(TextFormField)).dx,
    );
  });

  test('belacan is a fixed allergen', () {
    expect(ListingOptions.allergens, contains('belacan'));
    expect(allergenLabel('belacan'), 'Belacan');
  });

  test('tree nut is not a fixed allergen', () {
    expect(ListingOptions.allergens, isNot(contains('tree nut')));
    expect(ListingValidators.otherAllergens('Tree nut'), isNull);
  });

  group('pickup times', () {
    DateTime at(int hour, int minute, [int second = 0]) =>
        DateTime(2026, 11, 6, hour, minute, second);

    test('the default start is the next half hour', () {
      expect(PickupTimes.defaultStart(at(6, 1)), at(6, 30));
      expect(PickupTimes.defaultStart(at(6, 30)), at(6, 30));
      expect(PickupTimes.defaultStart(at(6, 30, 5)), at(7, 0));
      expect(PickupTimes.defaultStart(at(6, 31)), at(7, 0));
    });

    test('the defaults stay on the same day near midnight', () {
      expect(PickupTimes.defaultStart(at(23, 40)), at(23, 40));
      expect(PickupTimes.defaultEnd(at(6, 30)), at(8, 30));
      expect(PickupTimes.defaultEnd(at(23, 0)), at(23, 59));
    });

    test('a start that has passed is refused', () {
      expect(PickupTimes.startError(at(9, 59), at(10, 0, 30)), isNotNull);
      expect(PickupTimes.startError(at(10, 0), at(10, 0, 30)), isNull);
    });

    test('an end must follow the start and be in the future', () {
      expect(PickupTimes.endError(at(10, 0), at(11, 0), at(9, 0)), isNotNull);
      expect(PickupTimes.endError(at(10, 0), at(8, 0), at(10, 30)), isNotNull);
      expect(PickupTimes.endError(at(12, 0), at(11, 0), at(10, 0)), isNull);
    });
  });

  test('every category has its own icon', () {
    final icons = ListingOptions.categories.map(categoryIcon).toSet();
    expect(icons.length, ListingOptions.categories.length);
  });

  group('Listings tab', () {
    testWidgets('shows an empty state', (tester) async {
      await _pumpPages(tester, (_) async => jsonResponse({'listings': []}));

      expect(find.text('No listings yet'), findsOneWidget);
      expect(find.text('Add Listing'), findsOneWidget);
    });

    testWidgets('shows listing details in the order the server gives', (
      tester,
    ) async {
      await _pumpPages(
        tester,
        (_) async => jsonResponse({
          'listings': [
            _listingJson(id: 'l2', title: 'Newest', allergens: ['egg']),
            _listingJson(title: 'Older'),
          ],
        }),
      );

      final newest = tester.getTopLeft(find.text('Newest'));
      final older = tester.getTopLeft(find.text('Older'));
      expect(newest.dx, lessThan(older.dx));
      expect(find.text('RM 4.50'), findsNWidgets(2));
      expect(find.text('RM 8.00'), findsNWidgets(2));
      expect(find.text('6 in stock'), findsNWidgets(2));
      expect(find.text('Allergens: Egg'), findsOneWidget);
      expect(find.text('Allergens: None declared'), findsOneWidget);
    });

    testWidgets('shows an error with a way to try again', (tester) async {
      var calls = 0;
      await _pumpPages(tester, (_) async {
        calls++;
        return calls == 1
            ? jsonResponse({'error': 'Could not load.'}, 500)
            : jsonResponse({'listings': []});
      });

      expect(find.text('Could not load.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('No listings yet'), findsOneWidget);
    });
  });

  group('Add Listing', () {
    testWidgets('saves and the listing appears straight away', (tester) async {
      Map<String, dynamic>? sent;
      await _pumpPages(tester, (request) async {
        if (request.method == 'GET') return jsonResponse({'listings': []});
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({'listing': _listingJson()}, 201);
      });

      await _openForm(tester);
      await _fillForm(tester);
      await tester.tap(find.text('Egg'));
      await tester.pump();
      await _save(tester);

      expect(sent!['title'], 'Nasi Lemak');
      expect(sent!['category'], 'Rice');
      expect(sent!['isHalal'], true);
      expect(sent!['originalPrice'], 8);
      expect(sent!['discountedPrice'], 4.5);
      expect(sent!['quantityAvailable'], 6);
      expect(sent!['allergens'], ['egg']);
      expect(
        DateTime.parse(sent!['pickupStart'] as String).toLocal(),
        DateTime(2026, 11, 6, 18),
      );
      expect(
        DateTime.parse(sent!['pickupEnd'] as String).toLocal(),
        DateTime(2026, 11, 6, 20),
      );
      for (final field in ['vendor', 'location', 'status', 'imageUrl']) {
        expect(sent!.containsKey(field), isFalse, reason: field);
      }
      expect(find.text('Nasi Lemak'), findsOneWidget);
      expect(find.text('No listings yet'), findsNothing);
    });

    testWidgets('an empty form shows errors and sends nothing', (tester) async {
      var posts = 0;
      await _pumpPages(tester, (request) async {
        if (request.method == 'POST') posts++;
        return jsonResponse({'listings': []});
      });

      await _openForm(tester);
      await _save(tester);

      expect(posts, 0);
      expect(find.text('Check the highlighted fields.'), findsOneWidget);
      expect(find.text('Choose a category.'), findsOneWidget);
      expect(find.text('Choose Yes or No.'), findsOneWidget);
    });

    testWidgets('pickup opens with the next half hour and a 2-hour window', (
      tester,
    ) async {
      await _pumpPages(tester, (_) async => jsonResponse({'listings': []}));
      await _openForm(tester);

      expect(find.text('10:00 AM'), findsOneWidget);
      expect(find.text('12:00 PM'), findsOneWidget);
    });

    testWidgets('a passed start is refused as soon as it is picked', (
      tester,
    ) async {
      await _pumpPages(
        tester,
        (_) async => jsonResponse({'listings': []}),
        times: const [TimeOfDay(hour: 9, minute: 0)],
      );
      await _openForm(tester);

      await tester.tap(find.byIcon(Icons.schedule).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('That time has passed'), findsOneWidget);
      expect(find.text('10:00 AM'), findsOneWidget);
    });

    testWidgets('an end before the start is refused as soon as it is picked', (
      tester,
    ) async {
      await _pumpPages(
        tester,
        (_) async => jsonResponse({'listings': []}),
        times: const [TimeOfDay(hour: 9, minute: 30)],
      );
      await _openForm(tester);

      await tester.tap(find.byIcon(Icons.schedule).last);
      await tester.pumpAndSettle();

      expect(find.text('Pickup must end after it starts.'), findsOneWidget);
      expect(find.text('12:00 PM'), findsOneWidget);
    });

    testWidgets('moving the start past the end also moves the end', (
      tester,
    ) async {
      await _pumpPages(
        tester,
        (_) async => jsonResponse({'listings': []}),
        times: const [TimeOfDay(hour: 15, minute: 0)],
      );
      await _openForm(tester);

      await tester.tap(find.byIcon(Icons.schedule).first);
      await tester.pumpAndSettle();

      expect(find.text('3:00 PM'), findsOneWidget);
      expect(find.text('5:00 PM'), findsOneWidget);
    });

    testWidgets('halal starts with nothing selected', (tester) async {
      await _pumpPages(tester, (_) async => jsonResponse({'listings': []}));
      await _openForm(tester);

      final halal = tester.widget<SegmentedButton<bool>>(
        find.byType(SegmentedButton<bool>),
      );
      expect(halal.selected, isEmpty);
    });

    testWidgets('a server error shows and keeps the form open', (tester) async {
      await _pumpPages(tester, (request) async {
        if (request.method == 'GET') return jsonResponse({'listings': []});
        return jsonResponse({'error': 'Set up your profile first.'}, 404);
      });

      await _openForm(tester);
      await _fillForm(tester);
      await _save(tester);

      expect(find.text('Set up your profile first.'), findsOneWidget);
      expect(find.text('Save Listing'), findsOneWidget);
    });

    testWidgets('Save is disabled while saving', (tester) async {
      final response = Completer<http.Response>();
      var posts = 0;
      await _pumpPages(tester, (request) async {
        if (request.method == 'GET') return jsonResponse({'listings': []});
        posts++;
        return response.future;
      });

      await _openForm(tester);
      await _fillForm(tester);
      await tester.tap(find.text('Save Listing'));
      await tester.pump();

      expect(find.text('Save Listing'), findsNothing);
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      expect(posts, 1);

      response.complete(jsonResponse({'listing': _listingJson()}, 201));
      await tester.pumpAndSettle();
    });
  });

  group('AI allergen suggestions', () {
    MockClientHandler handler({
      required http.Response Function(http.Request) onSuggest,
      void Function(Map<String, dynamic>)? onCreate,
    }) => (request) async {
      if (request.method == 'GET') return jsonResponse({'listings': []});
      if (request.url.path.endsWith('allergen-suggestions')) {
        return onSuggest(request);
      }
      onCreate?.call(jsonDecode(request.body) as Map<String, dynamic>);
      return jsonResponse({'listing': _listingJson()}, 201);
    };

    Future<void> tapSuggest(WidgetTester tester) async {
      await tester.tap(find.text('SaveSpoon AI'));
      await tester.pumpAndSettle();
    }

    bool chipSelected(WidgetTester tester, String label) => tester
        .widget<FilterChip>(find.widgetWithText(FilterChip, label))
        .selected;

    testWidgets(
      'needs an item name first and sends only name and description',
      (tester) async {
        Map<String, dynamic>? sent;
        await _pumpPages(
          tester,
          handler(
            onSuggest: (request) {
              sent = jsonDecode(request.body) as Map<String, dynamic>;
              return jsonResponse({'allergens': []});
            },
          ),
        );

        await _openForm(tester);
        await tapSuggest(tester);
        expect(
          find.text('Item name must be 2 to 80 characters.'),
          findsOneWidget,
        );
        expect(sent, isNull);

        await _fillForm(tester);
        await tapSuggest(tester);
        expect(sent, {'title': 'Nasi Lemak'});
      },
    );

    testWidgets('selects chips, warns, and the vendor can change them', (
      tester,
    ) async {
      await _pumpPages(
        tester,
        handler(
          onSuggest: (_) => jsonResponse({
            'allergens': ['egg', 'gluten'],
          }),
        ),
      );

      await _openForm(tester);
      await _fillForm(tester);
      await tapSuggest(tester);

      expect(chipSelected(tester, 'Egg'), isTrue);
      expect(chipSelected(tester, 'Gluten'), isTrue);
      expect(
        find.text(
          'SaveSpoon AI can make mistakes. Check these allergens before saving.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Gluten'));
      await tester.pump();
      expect(chipSelected(tester, 'Gluten'), isFalse);
    });

    testWidgets('the button says Thinking while waiting and explains itself', (
      tester,
    ) async {
      final response = Completer<http.Response>();
      await _pumpPages(tester, (request) async {
        if (request.method == 'GET') return jsonResponse({'listings': []});
        return response.future;
      });

      await _openForm(tester);
      await _fillForm(tester);
      expect(find.textContaining('Let AI suggest them'), findsOneWidget);

      await tester.tap(find.text('SaveSpoon AI'));
      await tester.pump();
      expect(find.text('Thinking…'), findsOneWidget);

      response.complete(jsonResponse({'allergens': []}));
      await tester.pumpAndSettle();
      expect(find.text('SaveSpoon AI'), findsOneWidget);
    });

    testWidgets('AI fills other allergens, which the vendor can change', (
      tester,
    ) async {
      Map<String, dynamic>? created;
      await _pumpPages(
        tester,
        handler(
          onSuggest: (_) => jsonResponse({
            'allergens': ['egg'],
            'otherAllergens': ['Mango', 'Kiwi'],
          }),
          onCreate: (body) => created = body,
        ),
      );

      await _openForm(tester);
      await _fillForm(tester);
      await tapSuggest(tester);
      expect(find.text('Mango, Kiwi'), findsOneWidget);

      await tester.enterText(
        find.bySemanticsLabel('Other allergens (optional)'),
        'Mango',
      );
      await tester.tap(find.text("I've checked the allergens"));
      await tester.pump();
      await _save(tester);

      expect(created!['otherAllergens'], ['Mango']);
    });

    testWidgets('reaching the limit shows the message and manual entry works', (
      tester,
    ) async {
      Map<String, dynamic>? created;
      const message =
          "You've reached the AI suggestion limit. Try again in 30 min, "
          'or choose the allergens yourself.';
      await _pumpPages(
        tester,
        handler(
          onSuggest: (_) => jsonResponse({'error': message}, 429),
          onCreate: (body) => created = body,
        ),
      );

      await _openForm(tester);
      await _fillForm(tester);
      await tapSuggest(tester);
      expect(find.text(message), findsOneWidget);

      await tester.tap(find.text('Milk'));
      await tester.pump();
      await _save(tester);

      expect(created!['allergens'], ['milk']);
    });

    testWidgets('saving is blocked until the vendor confirms', (tester) async {
      Map<String, dynamic>? created;
      await _pumpPages(
        tester,
        handler(
          onSuggest: (_) => jsonResponse({
            'allergens': ['egg'],
          }),
          onCreate: (body) => created = body,
        ),
      );

      await _openForm(tester);
      await _fillForm(tester);
      await tapSuggest(tester);
      await _save(tester);

      expect(created, isNull);
      expect(
        find.text('Tick the box to confirm the allergens.'),
        findsOneWidget,
      );

      await tester.tap(find.text("I've checked the allergens"));
      await tester.pump();
      await _save(tester);

      expect(created!['allergens'], ['egg']);
    });

    testWidgets(
      'finding nothing warns that the food may not be free of allergens',
      (tester) async {
        await _pumpPages(
          tester,
          handler(onSuggest: (_) => jsonResponse({'allergens': []})),
        );

        await _openForm(tester);
        await _fillForm(tester);
        await tapSuggest(tester);

        expect(find.textContaining("doesn't mean"), findsOneWidget);
        expect(find.text("I've checked the allergens"), findsOneWidget);
      },
    );

    testWidgets('a failure shows a message and the vendor can still save', (
      tester,
    ) async {
      Map<String, dynamic>? created;
      await _pumpPages(
        tester,
        handler(
          onSuggest: (_) => jsonResponse({'error': 'AI unavailable.'}, 503),
          onCreate: (body) => created = body,
        ),
      );

      await _openForm(tester);
      await _fillForm(tester);
      await tapSuggest(tester);

      expect(find.text('AI unavailable.'), findsOneWidget);
      expect(find.text("I've checked the allergens"), findsNothing);

      await tester.tap(find.text('Milk'));
      await tester.pump();
      await _save(tester);

      expect(created!['allergens'], ['milk']);
    });
  });
}
