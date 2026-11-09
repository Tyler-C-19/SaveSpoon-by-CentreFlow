import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/core/widgets/auto_refresh.dart';
import 'package:savespoon/features/listings/data/listing_repository.dart';
import 'package:savespoon/features/listings/presentation/pages/vendor_listings_page.dart';

import 'helpers.dart';

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Map<String, dynamic> _listing(int stock) => {
  '_id': 'l1',
  'title': 'Nasi Lemak',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': stock,
  'pickupStart': _inHours(-1),
  'pickupEnd': _inHours(2),
  'allergens': const <String>[],
  'otherAllergens': const <String>[],
  'status': 'active',
};

Future<List<int>> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final calls = <int>[0];
  await tester.pumpWidget(
    Provider<ListingRepository>(
      create: (_) => ListingRepository(
        ApiClient(
          client: MockClient((request) async {
            calls[0]++;
            return jsonResponse({
              'listings': [_listing(calls[0] == 1 ? 3 : 0)],
            });
          }),
        ),
      ),
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: VendorListingsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('pulling down refreshes and shows sold-out food', (tester) async {
    final calls = await _open(tester);
    expect(find.text('Unlisted - No Stock'), findsNothing);

    await tester.fling(find.byType(GridView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(calls[0], 2);
    expect(find.text('Unlisted - No Stock'), findsOneWidget);
  });

  testWidgets('the tab refreshes itself while it is on screen', (tester) async {
    final calls = await _open(tester);

    await tester.pump(AutoRefresh.interval);
    await tester.pumpAndSettle();

    expect(calls[0], 2);
    expect(find.text('Unlisted - No Stock'), findsOneWidget);
  });
}
