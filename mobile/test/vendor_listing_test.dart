import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/pages/add_listing_page.dart';
import 'package:savespoon/features/listings/presentation/pages/relist_page.dart';
import 'package:savespoon/features/listings/presentation/pages/vendor_listing_page.dart';

import 'helpers.dart';

final DateTime _now = DateTime.now();

Map<String, dynamic> _json({
  int stock = 5,
  int sold = 3,
  String status = 'active',
  Duration endsIn = const Duration(hours: 2),
}) => {
  '_id': 'l1',
  'title': 'Nasi Lemak',
  'description': 'With sambal',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': stock,
  'soldCount': sold,
  'pickupStart': _now
      .subtract(const Duration(hours: 1))
      .toUtc()
      .toIso8601String(),
  'pickupEnd': _now.add(endsIn).toUtc().toIso8601String(),
  'allergens': ['egg'],
  'otherAllergens': <String>[],
  'status': status,
};

class _Server {
  _Server(this.listing);

  Map<String, dynamic> listing;
  int pastSold = 20;
  final List<http.Request> patches = [];
  http.Response? Function(http.Request request)? onPatch;

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'GET' &&
        request.url.path == '/api/listings/mine/l1') {
      return jsonResponse({'listing': listing, 'pastSold': pastSold});
    }
    if (request.method == 'PATCH') {
      patches.add(request);
      final reply = onPatch?.call(request);
      if (reply != null) return reply;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path.endsWith('/stock')) {
        listing = {...listing, 'quantityAvailable': body['quantity']};
      } else {
        listing = {
          ...listing,
          'status': body['paused'] == true ? 'paused' : 'active',
        };
      }
      return jsonResponse({'listing': listing});
    }
    return jsonResponse({'error': 'Not found'}, 404);
  }
}

Future<List<Listing>> _pump(
  WidgetTester tester,
  _Server server, {
  Listing? relisted,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final relistCalls = <Listing>[];
  await tester.pumpWidget(
    Provider<ListingRepository>(
      create: (_) =>
          ListingRepository(ApiClient(client: MockClient(server.handle))),
      child: MaterialApp(
        theme: AppTheme.light,
        home: VendorListingPage(
          listingId: 'l1',
          onRelist: (context, listing) async {
            relistCalls.add(listing);
            return relisted;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return relistCalls;
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.ancestor(
    of: find.text('Save Changes'),
    matching: find.byType(FilledButton),
  ),
);

Map<String, dynamic> _body(http.Request request) =>
    jsonDecode(request.body) as Map<String, dynamic>;

String? _figure(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

void main() {
  testWidgets('shows the listing with its stock, sold count and status', (
    tester,
  ) async {
    await _pump(tester, _Server(_json()));

    expect(find.text('Nasi Lemak'), findsWidgets);
    expect(find.text('Listed'), findsOneWidget);
    expect(find.text('Sold Today'), findsOneWidget);
    expect(find.text('Total Sold'), findsOneWidget);
    expect(_figure(tester, 'sold-today'), '3');
    expect(_figure(tester, 'total-sold'), '23');
    expect(find.text('With sambal'), findsOneWidget);
    expect(find.text('Egg'), findsOneWidget);
  });

  testWidgets('Save Changes is off until the stock changes, then saves it', (
    tester,
  ) async {
    final server = _Server(_json());
    await _pump(tester, server);

    expect(_saveButton(tester).onPressed, isNull);
    await tester.tap(find.byTooltip('More'));
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNotNull);
    await tester.tap(find.byTooltip('Less'));
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const ValueKey('stock-field')), '9');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(_body(server.patches.single), {
      'quantity': 9,
      'expectedQuantity': 5,
    });
    expect(find.text('Stock updated to 9.'), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('an order while editing asks before setting the stock', (
    tester,
  ) async {
    final server = _Server(_json());
    await _pump(tester, server);
    server.onPatch = (request) {
      if (server.patches.length > 1) return null;
      server.listing = _json(stock: 3, sold: 5);
      return jsonResponse({
        'code': 'STOCK_CHANGED',
        'current': 3,
        'error':
            '2 items were ordered while you were editing. '
            'Current available stock is now 3.',
      }, 409);
    };

    await tester.enterText(find.byKey(const ValueKey('stock-field')), '7');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.text('Stock Changed'), findsOneWidget);
    expect(
      find.text(
        '2 items were ordered while you were editing. '
        'Current available stock is now 3, Set it to 7 anyway?',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Keep 3'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Set to 7'), findsOneWidget);
    await tester.tap(find.text('Set to 7'));
    await tester.pumpAndSettle();

    expect(_body(server.patches.last), {'quantity': 7, 'expectedQuantity': 3});
    expect(find.text('Stock updated to 7.'), findsOneWidget);
  });

  testWidgets('keeping the new stock after an order saves nothing more', (
    tester,
  ) async {
    final server = _Server(_json());
    await _pump(tester, server);
    server.onPatch = (request) {
      server.listing = _json(stock: 4, sold: 4);
      return jsonResponse({
        'code': 'STOCK_CHANGED',
        'current': 4,
        'error':
            '1 item was ordered while you were editing. '
            'Current available stock is now 4.',
      }, 409);
    };

    await tester.enterText(find.byKey(const ValueKey('stock-field')), '8');
    await tester.pump();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep 4'));
    await tester.pumpAndSettle();

    expect(server.patches, hasLength(1));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('stock-field')))
          .controller!
          .text,
      '4',
    );
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('the switch turns the listing off and back on', (tester) async {
    final server = _Server(_json());
    await _pump(tester, server);

    await tester.tap(find.byKey(const ValueKey('shown-switch')));
    await tester.pumpAndSettle();
    expect(_body(server.patches.last), {'paused': true});
    expect(find.text('Unlisted - Turned Off'), findsOneWidget);
    expect(
      find.text(
        'Orders already placed still need to be prepared and collected.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('shown-switch')));
    await tester.pumpAndSettle();
    expect(_body(server.patches.last), {'paused': false});
    expect(find.text('Listed'), findsOneWidget);
  });

  testWidgets('a sold-out listing explains that restocking puts it back', (
    tester,
  ) async {
    await _pump(tester, _Server(_json(stock: 0, sold: 12)));

    expect(find.text('Unlisted - No Stock'), findsOneWidget);
    expect(
      find.textContaining(
        'Adding stock puts this item back on sale until pickup',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Sold so far:'), findsNothing);
    expect(find.text('Relist'), findsNothing);
    expect(find.byKey(const ValueKey('listing-image')), findsOneWidget);
    final sold = tester.widget<Text>(find.byKey(const ValueKey('sold-today')));
    expect(sold.data, '12');
    expect(sold.style?.color, AppTheme.light.colorScheme.primary);
  });

  testWidgets('after pickup ends, figures are fixed and Relist replaces Save', (
    tester,
  ) async {
    final relisted = Listing.fromJson({..._json(), '_id': 'l2'});
    final calls = await _pump(
      tester,
      _Server(_json(endsIn: const Duration(hours: -1))),
      relisted: relisted,
    );

    expect(
      find.text(
        'Pickup window has ended for today. Relist to put it back on sale.',
      ),
      findsOneWidget,
    );
    expect(find.text('Save Changes'), findsNothing);
    expect(find.byKey(const ValueKey('stock-field')), findsNothing);
    expect(_figure(tester, 'stock-left'), '5');
    expect(_figure(tester, 'sold-today'), '3');
    expect(_figure(tester, 'total-sold'), '23');
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('shown-switch')))
          .onChanged,
      isNull,
    );
    expect(find.text('Pickup window has ended for today.'), findsOneWidget);
    expect(find.text('Relist'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('relist-button')));
    await tester.pumpAndSettle();
    expect(calls.single.id, 'l1');
  });

  testWidgets('a missing listing shows the error with Try again', (
    tester,
  ) async {
    final server = _Server(_json());
    await tester.pumpWidget(
      Provider<ListingRepository>(
        create: (_) => ListingRepository(
          ApiClient(
            client: MockClient(
              (_) async => jsonResponse({
                'code': 'LISTING_NOT_FOUND',
                'error': 'Listing not found.',
              }, 404),
            ),
          ),
        ),
        child: MaterialApp(
          home: VendorListingPage(
            listingId: 'l1',
            onRelist: (context, listing) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Listing not found.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(server.patches, isEmpty);
  });

  testWidgets('relisting reloads the page with the new round', (tester) async {
    final server = _Server(_json(endsIn: const Duration(hours: -1)));
    final relisted = Listing.fromJson(_json(stock: 15, sold: 0));
    final calls = <Listing>[];
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Provider<ListingRepository>(
        create: (_) =>
            ListingRepository(ApiClient(client: MockClient(server.handle))),
        child: MaterialApp(
          theme: AppTheme.light,
          home: VendorListingPage(
            listingId: 'l1',
            onRelist: (context, listing) async {
              calls.add(listing);
              server.listing = _json(stock: 15, sold: 0);
              server.pastSold = 23;
              return relisted;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Relist'));
    await tester.pumpAndSettle();

    expect(calls.single.id, 'l1');
    expect(find.text('Nasi Lemak is back on sale.'), findsOneWidget);
    expect(find.text('Relist'), findsNothing);
    expect(_figure(tester, 'sold-today'), '0');
    expect(_figure(tester, 'total-sold'), '23');
  });

  group('Relist Item page', () {
    final fixedNow = DateTime(2026, 11, 6, 10);
    final ended = Listing.fromJson({
      ..._json(),
      'pickupEnd': DateTime(2026, 11, 6, 8).toUtc().toIso8601String(),
    });

    Future<(List<http.Request>, List<Object?>)> pumpRelist(
      WidgetTester tester, {
      http.Response? reply,
    }) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final requests = <http.Request>[];
      final results = <Object?>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    results.add(await context.push<Listing>('/relist')),
                child: const Text('Open'),
              ),
            ),
          ),
          GoRoute(
            path: '/relist',
            builder: (context, state) =>
                RelistPage(listing: ended, now: () => fixedNow),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        Provider<ListingRepository>(
          create: (_) => ListingRepository(
            ApiClient(
              client: MockClient((request) async {
                requests.add(request);
                return reply ??
                    jsonResponse({
                      'listing': _json(stock: 15, sold: 0),
                      'pastSold': 13,
                    });
              }),
            ),
          ),
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      return (requests, results);
    }

    testWidgets('shows a summary and asks only for stock and pickup time', (
      tester,
    ) async {
      await pumpRelist(tester);

      expect(find.text('Relist Item'), findsWidgets);
      expect(find.text('Nasi Lemak'), findsOneWidget);
      expect(find.text('RM 4.50'), findsOneWidget);
      final was = tester.widget<Text>(find.text('RM 8.00'));
      expect(was.style?.decoration, TextDecoration.lineThrough);
      expect(was.style?.color, AppColors.textMuted);
      expect(find.text('Allergens: Egg'), findsOneWidget);
      expect(find.text('Pickup time today'), findsOneWidget);
      expect(
        find.text('Other details can be edited while the listing is live.'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('sends stock and today\'s pickup times, then returns', (
      tester,
    ) async {
      final (requests, results) = await pumpRelist(tester);

      await tester.enterText(find.byType(TextFormField), '15');
      await tester.tap(find.widgetWithText(FilledButton, 'Relist Item'));
      await tester.pumpAndSettle();

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/listings/l1/relist');
      final body = _body(request);
      expect(body['quantityAvailable'], 15);
      expect(
        DateTime.parse(body['pickupStart'] as String).toLocal(),
        DateTime(2026, 11, 6, 10),
      );
      expect(
        DateTime.parse(body['pickupEnd'] as String).toLocal(),
        DateTime(2026, 11, 6, 12),
      );
      expect(body['paused'], false);
      expect((results.single as Listing).quantityAvailable, 15);
    });

    testWidgets('Show to Customers off relists it turned off', (tester) async {
      final (requests, _) = await pumpRelist(tester);

      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('relist-shown-switch')),
            )
            .value,
        isTrue,
      );
      expect(find.text('Availability'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('relist-shown-switch')));
      await tester.pump();
      expect(
        find.text(
          'Customers won\'t see this yet. Turn it on from the listing when '
          'you\'re ready.',
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextFormField), '8');
      await tester.tap(find.widgetWithText(FilledButton, 'Relist Item'));
      await tester.pumpAndSettle();
      expect(_body(requests.single)['paused'], true);
    });

    testWidgets('empty stock or a server error keeps the page open', (
      tester,
    ) async {
      final (requests, results) = await pumpRelist(
        tester,
        reply: jsonResponse({
          'code': 'ALREADY_RELISTED',
          'error': 'This item has already been relisted.',
        }, 409),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Relist Item'));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(find.text('Check the highlighted fields.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '5');
      await tester.tap(find.widgetWithText(FilledButton, 'Relist Item'));
      await tester.pumpAndSettle();
      expect(find.text('This item has already been relisted.'), findsOneWidget);
      expect(results, isEmpty);
    });
  });

  group('Same name warning', () {
    final fixedNow = DateTime(2026, 11, 6, 10);
    Listing existing({required int endHour}) => Listing.fromJson({
      ..._json(),
      'pickupEnd': DateTime(2026, 11, 6, endHour).toUtc().toIso8601String(),
    });

    final opened = <String>[];

    Future<(List<http.Request>, List<Object?>)> pumpAdd(
      WidgetTester tester,
      Listing? mine, {
      Listing? relistResult,
      http.Response? reply,
      bool save = true,
    }) async {
      tester.view.physicalSize = const Size(1200, 3400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      opened.clear();
      final requests = <http.Request>[];
      final results = <Object?>[];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    results.add(await context.push<Listing>('/add')),
                child: const Text('Open'),
              ),
            ),
          ),
          GoRoute(
            path: '/add',
            builder: (context, state) => AddListingPage(
              now: () => fixedNow,
              existing: [?mine],
              onOpenExisting: (context, listing) async {
                opened.add('open ${listing.id}');
                return null;
              },
              onRelistExisting: (context, listing) async {
                opened.add('relist ${listing.id}');
                return relistResult;
              },
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        Provider<ListingRepository>(
          create: (_) => ListingRepository(
            ApiClient(
              client: MockClient((request) async {
                requests.add(request);
                return reply ??
                    jsonResponse({
                      'listing': {..._json(), '_id': 'new'},
                    }, 201);
              }),
            ),
          ),
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.bySemanticsLabel('Item name'),
        ' nasi  LEMAK ',
      );
      await tester.enterText(find.bySemanticsLabel('Original (RM)'), '8');
      await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '4.50');
      await tester.enterText(find.bySemanticsLabel('Stock'), '6');
      await tester.tap(find.text('Rice'));
      await tester.tap(find.text('Yes'));
      await tester.pump();
      if (save) {
        await tester.tap(find.text('Save Listing'));
        await tester.pumpAndSettle();
      }
      return (requests, results);
    }

    testWidgets('Relist It relists and closes the form', (tester) async {
      final ended = existing(endHour: 8);
      final (requests, results) = await pumpAdd(
        tester,
        ended,
        relistResult: ended,
      );

      expect(find.text('Same Item Found'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            "You already have a listing for Nasi Lemak, but it's unlisted.",
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Create New'), findsNothing);
      final cancel = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Cancel'),
      );
      expect(
        cancel.style?.foregroundColor?.resolve({}),
        AppTheme.light.colorScheme.error,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Relist It'));
      await tester.pumpAndSettle();

      expect(opened, ['relist l1']);
      expect(requests, isEmpty);
      expect((results.single as Listing).id, 'l1');
    });

    testWidgets('backing out of Relist returns to the filled form', (
      tester,
    ) async {
      final (requests, results) = await pumpAdd(tester, existing(endHour: 8));

      await tester.tap(find.widgetWithText(FilledButton, 'Relist It'));
      await tester.pumpAndSettle();

      expect(opened, ['relist l1']);
      expect(results, isEmpty);
      expect(find.text('Save Listing'), findsOneWidget);
      expect(find.text(' nasi  LEMAK '), findsOneWidget);
    });

    testWidgets('View Listing shows the listing, then the form as it was', (
      tester,
    ) async {
      final (requests, results) = await pumpAdd(tester, existing(endHour: 12));

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            "You already have a listing for Nasi Lemak, and it's active.",
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'View Listing'));
      await tester.pumpAndSettle();

      expect(opened, ['open l1']);
      expect(results, isEmpty);
      expect(requests, isEmpty);
      expect(find.text(' nasi  LEMAK '), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('Cancel closes the form and returns to the previous page', (
      tester,
    ) async {
      final (requests, results) = await pumpAdd(tester, existing(endHour: 12));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Same Item Found'), findsNothing);
      expect(find.text('Save Listing'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(results, [null]);
      expect(opened, isEmpty);
      expect(requests, isEmpty);
    });

    testWidgets('a different name saves normally', (tester) async {
      final other = Listing.fromJson({
        ..._json(),
        'title': 'Nasi Lemak (Large)',
      });
      final (requests, results) = await pumpAdd(tester, other);

      expect(find.text('Same Item Found'), findsNothing);
      expect(requests.single.url.path, '/api/listings');
      expect((results.single as Listing).id, 'new');
    });

    testWidgets('typing a name already used shows a note with Relist It', (
      tester,
    ) async {
      final ended = existing(endHour: 8);
      final (requests, results) = await pumpAdd(
        tester,
        ended,
        relistResult: ended,
        save: false,
      );

      final note = find.byKey(const ValueKey('same-item-note'));
      expect(note, findsOneWidget);
      expect(
        find.descendant(
          of: note,
          matching: find.text(
            "You already have a listing for Nasi Lemak, but it's unlisted.",
          ),
        ),
        findsOneWidget,
      );
      // It sits right under the Item name field.
      expect(
        tester.getTopLeft(note).dy,
        lessThan(
          tester.getTopLeft(find.bySemanticsLabel('Description (optional)')).dy,
        ),
      );

      await tester.tap(
        find.descendant(of: note, matching: find.text('Relist It')),
      );
      await tester.pumpAndSettle();
      expect(opened, ['relist l1']);
      expect(requests, isEmpty);
      expect((results.single as Listing).id, 'l1');
    });

    testWidgets('the note offers View Listing for a listed item and goes '
        'when the name changes', (tester) async {
      await pumpAdd(tester, existing(endHour: 12), save: false);

      final note = find.byKey(const ValueKey('same-item-note'));
      expect(
        find.descendant(
          of: note,
          matching: find.text(
            "You already have a listing for Nasi Lemak, and it's active.",
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: note, matching: find.text('View Listing')),
      );
      await tester.pumpAndSettle();
      expect(opened, ['open l1']);
      expect(find.text('Save Listing'), findsOneWidget);

      await tester.enterText(
        find.bySemanticsLabel('Item name'),
        'Nasi Lemak 2',
      );
      await tester.pump();
      expect(note, findsNothing);
    });

    testWidgets('a turned-off item reads as unlisted with View Listing', (
      tester,
    ) async {
      final off = Listing.fromJson({
        ..._json(status: 'paused'),
        'pickupEnd': DateTime(2026, 11, 6, 12).toUtc().toIso8601String(),
      });
      await pumpAdd(tester, off);

      expect(find.text('Same Item Found'), findsOneWidget);
      expect(
        find.text(
          "You already have a listing for Nasi Lemak, but it's unlisted.",
        ),
        findsNWidgets(2),
        reason: 'the note under the field and the popup say the same',
      );
      expect(find.textContaining('instead?'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'View Listing'), findsOneWidget);
    });

    testWidgets('the server refusing a same name shows its message', (
      tester,
    ) async {
      final (requests, results) = await pumpAdd(
        tester,
        null,
        reply: jsonResponse({
          'code': 'SAME_NAME',
          'listingId': 'l1',
          'error': 'You already have a listing called nasi  LEMAK.',
        }, 409),
      );

      expect(requests.single.url.path, '/api/listings');
      expect(
        find.text('You already have a listing called nasi  LEMAK.'),
        findsOneWidget,
      );
      expect(results, isEmpty);
      expect(find.text('Save Listing'), findsOneWidget);
    });
  });

  test('a paused listing is labelled Turned Off until pickup ends', () {
    final paused = Listing.fromJson(_json(status: 'paused'));
    expect(paused.unlistedLabelAt(_now), 'Unlisted - Turned Off');
    expect(paused.canChangeAt(_now), isTrue);
    expect(paused.canRelistAt(_now), isFalse);

    final ended = Listing.fromJson(
      _json(status: 'paused', endsIn: const Duration(hours: -1)),
    );
    expect(ended.unlistedLabelAt(_now), 'Unlisted - Pickup Ended');
    expect(ended.canChangeAt(_now), isFalse);
    expect(ended.canRelistAt(_now), isTrue);
  });
}
