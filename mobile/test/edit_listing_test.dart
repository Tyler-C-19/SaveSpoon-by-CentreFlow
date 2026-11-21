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

import 'helpers.dart';

final DateTime _today = DateTime.now();
final DateTime _now = DateTime(_today.year, _today.month, _today.day, 12);
final DateTime _start = DateTime(_today.year, _today.month, _today.day, 11);
final DateTime _end = DateTime(_today.year, _today.month, _today.day, 14);

Map<String, dynamic> _json({
  String id = 'l1',
  String title = 'Nasi Lemak',
  int stock = 5,
}) => {
  '_id': id,
  'title': title,
  'description': 'With sambal',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': stock,
  'soldCount': 3,
  'pickupStart': _start.toUtc().toIso8601String(),
  'pickupEnd': _end.toUtc().toIso8601String(),
  'allergens': ['egg'],
  'otherAllergens': <String>[],
  'status': 'active',
};

class _Server {
  int activeOrders = 0;
  int stock = 5;
  final List<Map<String, dynamic>> patches = [];
  http.Response? Function(Map<String, dynamic> body)? onPatch;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/api/listings/mine/l1') {
      return jsonResponse({
        'listing': _json(stock: stock),
        'pastSold': 0,
        'activeOrderCount': activeOrders,
      });
    }
    if (request.method == 'GET' && path == '/api/listings/mine') {
      return jsonResponse({
        'listings': [_json(), _json(id: 'l2', title: 'Mee Goreng')],
      });
    }
    if (request.method == 'PATCH' && path == '/api/listings/l1') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      patches.add(body);
      final reply = onPatch?.call(body);
      if (reply != null) return reply;
      return jsonResponse({
        'listing': {..._json(), 'title': body['title']},
      });
    }
    return jsonResponse({'error': 'Not found'}, 404);
  }
}

class _Opened {
  final List<Object?> results = [];
  final List<String> timePicks = [];
}

Future<_Opened> _pump(WidgetTester tester, _Server server) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = _Opened();
  final listing = Listing.fromJson(_json());
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                opened.results.add(await context.push<Listing>('/edit')),
            child: const Text('Open'),
          ),
        ),
      ),
      GoRoute(
        path: '/edit',
        builder: (context, state) => AddListingPage(
          editing: listing,
          now: () => _now,
          timePicker: (context, initial) async {
            opened.timePicks.add('$initial');
            return const TimeOfDay(hour: 15, minute: 0);
          },
          onViewOrders: (context) => opened.results.add('orders'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    Provider<ListingRepository>(
      create: (_) =>
          ListingRepository(ApiClient(client: MockClient(server.handle))),
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return opened;
}

FilledButton _save(WidgetTester tester) => tester.widget<FilledButton>(
  find.ancestor(
    of: find.text('Save Changes'),
    matching: find.byType(FilledButton),
  ),
);

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save Changes'));
  await tester.tap(find.text('Save Changes'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'opens filled in, with Save Changes off until something changes',
    (tester) async {
      await _pump(tester, _Server());

      expect(find.text('Edit Listing'), findsOneWidget);
      expect(find.text('Nasi Lemak'), findsOneWidget);
      expect(find.text('With sambal'), findsOneWidget);
      expect(find.text('8.00'), findsOneWidget);
      expect(find.text('4.50'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Save Listing'), findsNothing);
      expect(_save(tester).onPressed, isNull);

      await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '4.00');
      await tester.pump();
      expect(_save(tester).onPressed, isNotNull);

      await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '4.5');
      await tester.pump();
      expect(_save(tester).onPressed, isNull);
    },
  );

  testWidgets('saves the changes and keeps an untouched pickup window exact', (
    tester,
  ) async {
    final server = _Server();
    final opened = await _pump(tester, server);

    await tester.enterText(
      find.bySemanticsLabel('Item name'),
      'Nasi Lemak Ayam',
    );
    await tester.enterText(find.bySemanticsLabel('Stock'), '0');
    await tester.pump();
    await _tapSave(tester);

    final body = server.patches.single;
    expect(body['title'], 'Nasi Lemak Ayam');
    expect(body['quantityAvailable'], 0);
    expect(body['expectedQuantity'], 5);
    expect(body['pickupStart'], _start.toUtc().toIso8601String());
    expect(body['pickupEnd'], _end.toUtc().toIso8601String());
    expect(body['allergens'], ['egg']);
    expect((opened.results.single as Listing?)?.title, 'Nasi Lemak Ayam');
  });

  testWidgets('an order during the edit asks before setting stock anyway', (
    tester,
  ) async {
    final server = _Server()..stock = 3;
    server.onPatch = (body) => body['expectedQuantity'] == 5
        ? jsonResponse({
            'code': 'STOCK_CHANGED',
            'error':
                '2 items were ordered while you were editing. '
                'Current available stock is now 3.',
          }, 409)
        : null;
    await _pump(tester, server);

    await tester.enterText(find.bySemanticsLabel('Stock'), '9');
    await tester.pump();
    await _tapSave(tester);

    expect(find.text('Stock Changed'), findsOneWidget);
    await tester.tap(find.text('Set to 9'));
    await tester.pumpAndSettle();

    expect(server.patches, hasLength(2));
    expect(server.patches.last['expectedQuantity'], 3);
    expect(server.patches.last['quantityAvailable'], 9);
  });

  testWidgets('keeping the new stock still saves the other changes', (
    tester,
  ) async {
    final server = _Server()..stock = 3;
    server.onPatch = (body) => body['expectedQuantity'] == 5
        ? jsonResponse({'code': 'STOCK_CHANGED', 'error': 'Changed.'}, 409)
        : null;
    await _pump(tester, server);

    await tester.enterText(find.bySemanticsLabel('Stock'), '9');
    await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '4');
    await tester.pump();
    await _tapSave(tester);
    await tester.tap(find.text('Keep 3'));
    await tester.pumpAndSettle();

    expect(server.patches.last['quantityAvailable'], 3);
    expect(server.patches.last['expectedQuantity'], 3);
    expect(server.patches.last['discountedPrice'], 4);
  });

  testWidgets('active orders lock the pickup time and flag halal changes', (
    tester,
  ) async {
    final server = _Server()..activeOrders = 2;
    final opened = await _pump(tester, server);

    expect(find.text('Locked while 2 orders are active.'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
    final startTime = tester.widget<Text>(find.text('11:00 AM'));
    expect(startTime.style?.color, isNotNull);
    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(opened.timePicks, isEmpty);

    expect(find.byKey(const ValueKey('ordered-note')), findsNothing);
    await tester.ensureVisible(find.text('No'));
    await tester.tap(find.text('No'));
    await tester.pump();
    expect(
      find.text("Customers who already ordered aren't told about this change."),
      findsOneWidget,
    );
  });

  testWidgets('View Active Orders opens the Orders tab straight away', (
    tester,
  ) async {
    final opened = await _pump(tester, _Server()..activeOrders = 1);

    expect(find.text('Locked while 1 order is active.'), findsOneWidget);
    await tester.tap(find.text('View Active Orders'));
    await tester.pumpAndSettle();
    expect(opened.results, ['orders']);
  });

  testWidgets('View Active Orders asks first when there are unsaved changes', (
    tester,
  ) async {
    final opened = await _pump(tester, _Server()..activeOrders = 1);

    await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '4');
    await tester.pump();
    await tester.tap(find.text('View Active Orders'));
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);

    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();
    expect(opened.results, isEmpty);

    await tester.tap(find.text('View Active Orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(opened.results, ['orders']);
  });

  testWidgets('Back with unsaved changes asks first', (tester) async {
    final opened = await _pump(tester, _Server());

    await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '4');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);

    await tester.tap(find.text('Keep Editing'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Listing'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Listing'), findsNothing);
    expect(opened.results, [null]);
  });

  testWidgets('Back with nothing changed leaves straight away', (tester) async {
    await _pump(tester, _Server());

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsNothing);
    expect(find.text('Edit Listing'), findsNothing);
  });

  testWidgets('without active orders the pickup time can move', (tester) async {
    final server = _Server();
    final opened = await _pump(tester, server);

    await tester.ensureVisible(find.text('End'));
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    expect(opened.timePicks, hasLength(1));
    await _tapSave(tester);

    final end = DateTime.parse(server.patches.single['pickupEnd'] as String);
    expect(end.toLocal().hour, 15);
  });

  testWidgets('a locked pickup time from the server is put back', (
    tester,
  ) async {
    final server = _Server();
    server.onPatch = (_) => jsonResponse({
      'code': 'PICKUP_LOCKED',
      'error': "Pickup time can't change while you have active orders.",
    }, 409);
    await _pump(tester, server);

    await tester.ensureVisible(find.text('End'));
    await tester.tap(find.text('End'));
    await tester.pumpAndSettle();
    await _tapSave(tester);

    expect(find.byKey(const ValueKey('pickup-locked')), findsOneWidget);
    expect(find.text('Edit Listing'), findsOneWidget);
  });

  testWidgets(
    "renaming to another item's name warns and Cancel keeps the form",
    (tester) async {
      final server = _Server();
      await _pump(tester, server);

      await tester.enterText(find.bySemanticsLabel('Item name'), 'mee  goreng');
      await tester.pump();
      expect(find.byKey(const ValueKey('same-item-note')), findsOneWidget);

      await _tapSave(tester);
      expect(find.text('Same Item Found'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Listing'), findsOneWidget);
      expect(server.patches, isEmpty);
    },
  );

  testWidgets('its own name does not count as the same item', (tester) async {
    await _pump(tester, _Server());

    await tester.enterText(find.bySemanticsLabel('Item name'), 'nasi lemak');
    await tester.pump();
    expect(find.byKey(const ValueKey('same-item-note')), findsNothing);
  });
}
