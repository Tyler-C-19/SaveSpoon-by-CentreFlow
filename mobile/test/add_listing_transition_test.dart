import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'helpers.dart';

final Map<String, dynamic> _vendor = {
  ...userJson,
  'role': 'vendor',
  'hasVendorProfile': true,
};

Map<String, dynamic> _savedListing() {
  final now = DateTime.now();
  return {
    '_id': 'l1',
    'title': 'Nasi Lemak',
    'category': 'Rice',
    'isHalal': true,
    'originalPrice': 8,
    'discountedPrice': 4.5,
    'quantityAvailable': 6,
    'pickupStart': now.toUtc().toIso8601String(),
    'pickupEnd': now.add(const Duration(hours: 1)).toUtc().toIso8601String(),
    'allergens': <String>[],
    'status': 'active',
  };
}

var _saved = false;

Future<http.Response> _server(http.Request request) async {
  if (request.url.path == '/api/listings/mine') {
    return jsonResponse({
      'listings': [if (_saved) _savedListing()],
    });
  }
  if (request.url.path == '/api/listings') {
    _saved = true;
    return jsonResponse({'listing': _savedListing()}, 201);
  }
  return jsonResponse({
    'user': _vendor,
    'vendor': {'description': 'Rice'},
  });
}

Future<void> _openListingsTab(WidgetTester tester) async {
  _saved = false;
  await startApp(
    tester,
    storage: FakeTokenStorage(token: 'saved'),
    onRequest: _server,
  );
  await tester.tap(find.text('Listings'));
  await tester.pumpAndSettle();
}

void main() {
  final pageTitle = find.text('Add a Listing');

  testWidgets('the page slides in from the right', (tester) async {
    await _openListingsTab(tester);

    await tester.tap(find.text('Add Listing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final moving = tester.getTopLeft(pageTitle);

    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(pageTitle);

    expect(moving.dx, greaterThan(settled.dx));
    expect(moving.dy, settled.dy);
  });

  testWidgets('going back slides the page out to the right', (tester) async {
    await _openListingsTab(tester);
    await tester.tap(find.text('Add Listing'));
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(pageTitle);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));

    expect(tester.getTopLeft(pageTitle).dx, greaterThan(settled.dx));

    await tester.pumpAndSettle();
    expect(pageTitle, findsNothing);
    expect(find.text('All Listings'), findsOneWidget);
  });

  testWidgets('a saved listing still appears after sliding back', (
    tester,
  ) async {
    await _openListingsTab(tester);
    await tester.tap(find.text('Add Listing'));
    await tester.pumpAndSettle();

    await tester.enterText(find.bySemanticsLabel('Item name'), 'Nasi Lemak');
    await tester.enterText(find.bySemanticsLabel('Original (RM)'), '8');
    await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '4.50');
    await tester.enterText(find.bySemanticsLabel('Stock'), '6');
    await tester.tap(find.text('Rice'));
    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.tap(find.text('Save Listing'));
    await tester.pumpAndSettle();

    expect(pageTitle, findsNothing);
    expect(find.text('Nasi Lemak'), findsOneWidget);
    expect(find.text('No listings yet'), findsNothing);
  });

  for (final (name, button, pageText) in [
    ('Forgot password', find.text('Forgot password?'), 'Forgot password'),
    (
      'Email sign-up',
      find.text('Email').last,
      'Already have an account? Log in',
    ),
  ]) {
    testWidgets('$name on the login page slides in and back out', (
      tester,
    ) async {
      await startApp(
        tester,
        storage: FakeTokenStorage(),
        onRequest: (_) async => jsonResponse({'error': 'Log in.'}, 401),
      );
      final page = find.text(pageText);

      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final moving = tester.getTopLeft(page);

      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(page);
      expect(moving.dx, greaterThan(settled.dx));
      expect(moving.dy, settled.dy);

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      expect(tester.getTopLeft(page).dx, greaterThan(settled.dx));

      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(button, findsOneWidget);
    });
  }
}
