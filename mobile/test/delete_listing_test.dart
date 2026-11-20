import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/pages/vendor_listing_page.dart';

import 'helpers.dart';

final DateTime _now = DateTime.now();

Map<String, dynamic> _json({Duration endsIn = const Duration(hours: 2)}) => {
  '_id': 'l1',
  'title': 'Nasi Lemak',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': 5,
  'soldCount': 3,
  'pickupStart': _now
      .subtract(const Duration(hours: 3))
      .toUtc()
      .toIso8601String(),
  'pickupEnd': _now.add(endsIn).toUtc().toIso8601String(),
  'allergens': <String>[],
  'otherAllergens': <String>[],
  'status': 'active',
};

class _Server {
  _Server({this.activeOrders = 0, this.endsIn = const Duration(hours: 2)});

  int activeOrders;
  final Duration endsIn;
  http.Response? deleteReply;
  final List<http.Request> deletes = [];

  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'GET' &&
        request.url.path == '/api/listings/mine/l1') {
      return jsonResponse({
        'listing': _json(endsIn: endsIn),
        'pastSold': 0,
        'activeOrderCount': activeOrders,
      });
    }
    if (request.method == 'DELETE' && request.url.path == '/api/listings/l1') {
      deletes.add(request);
      return deleteReply ?? jsonResponse({'deleted': true, 'listingId': 'l1'});
    }
    return jsonResponse({'error': 'Not found'}, 404);
  }
}

Future<List<Listing>> _pump(
  WidgetTester tester,
  _Server server, {
  Listing? edited,
  VoidCallback? onViewOrders,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final edits = <Listing>[];
  await tester.pumpWidget(
    Provider<ListingRepository>(
      create: (_) =>
          ListingRepository(ApiClient(client: MockClient(server.handle))),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VendorListingPage(
                    listingId: 'l1',
                    onRelist: (context, listing) async => null,
                    onEdit: (context, listing) async {
                      edits.add(listing);
                      return edited;
                    },
                    onViewOrders: onViewOrders == null
                        ? null
                        : (_) => onViewOrders(),
                  ),
                ),
              ),
              child: const Text('Listings tab'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Listings tab'));
  await tester.pumpAndSettle();
  return edits;
}

Future<void> _tapDelete(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('delete-listing')));
  await tester.tap(find.byKey(const ValueKey('delete-listing')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a live listing shows Edit Listing and Delete Listing', (
    tester,
  ) async {
    final edits = await _pump(
      tester,
      _Server(),
      edited: Listing.fromJson(_json()),
    );

    expect(find.text('Edit Listing'), findsOneWidget);
    expect(find.text('Delete Listing'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('edit-listing')));
    await tester.tap(find.byKey(const ValueKey('edit-listing')));
    await tester.pumpAndSettle();
    expect(edits.single.id, 'l1');
    expect(find.text('Changes saved.'), findsOneWidget);
  });

  testWidgets('an ended listing can be deleted but not edited', (tester) async {
    await _pump(tester, _Server(endsIn: const Duration(hours: -1)));

    expect(find.text('Edit Listing'), findsNothing);
    expect(find.text('Delete Listing'), findsOneWidget);
  });

  testWidgets('active orders lock Delete Listing with a short note', (
    tester,
  ) async {
    final server = _Server(activeOrders: 2);
    final viewed = <String>[];
    await _pump(tester, server, onViewOrders: () => viewed.add('orders'));

    final delete = tester.widget<FilledButton>(
      find.byKey(const ValueKey('delete-listing')),
    );
    expect(delete.onPressed, isNull);
    expect(find.text('Locked while 2 orders are active.'), findsOneWidget);

    await _tapDelete(tester);
    expect(find.text('Delete this listing?'), findsNothing);
    expect(server.deletes, isEmpty);

    await tester.tap(find.text('View Active Orders'));
    expect(viewed, ['orders']);
  });

  testWidgets('two warnings, then the listing is deleted and the page closes', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);

    await _tapDelete(tester);
    expect(find.text('Delete this listing?'), findsOneWidget);
    expect(find.text('Sales figures for this item are kept.'), findsOneWidget);
    expect(
      find.text("Deletion is permanent and can't be undone."),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Are you sure?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete Listing'));
    await tester.pumpAndSettle();

    expect(server.deletes, hasLength(1));
    expect(find.text('Listings tab'), findsOneWidget);
    expect(find.text('Nasi Lemak deleted.'), findsOneWidget);
  });

  testWidgets('Keep Listing at the second warning deletes nothing', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);

    await _tapDelete(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep Listing'));
    await tester.pumpAndSettle();

    expect(server.deletes, isEmpty);
    expect(find.text('Delete Listing'), findsOneWidget);
  });

  testWidgets('an order placed just before deleting still blocks it', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    server
      ..activeOrders = 1
      ..deleteReply = jsonResponse({
        'code': 'ACTIVE_ORDERS',
        'activeOrderCount': 1,
        'error': 'You have 1 active order for this item.',
      }, 409);

    await _tapDelete(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete Listing'));
    await tester.pumpAndSettle();

    expect(find.text("Can't Delete Yet"), findsOneWidget);
    expect(
      find.textContaining('You have 1 active order for Nasi Lemak'),
      findsOneWidget,
    );
  });
}
