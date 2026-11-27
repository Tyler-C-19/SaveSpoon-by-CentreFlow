import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/listings/data/favourites_repository.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/listings/presentation/providers/favourites_provider.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_card.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_image.dart';
import 'package:savespoon/features/listings/presentation/widgets/quick_add_button.dart';
import 'package:savespoon/features/listings/presentation/widgets/search_result_row.dart';
import 'package:savespoon/features/map/data/position_source.dart';
import 'package:savespoon/features/map/presentation/providers/user_location_provider.dart';
import 'package:savespoon/features/map/presentation/widgets/distance_pill.dart';
import 'package:savespoon/features/seller_profile/domain/geo_point.dart';

import 'helpers.dart';

// Android 14+ grows small text more than large text.
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

const _widths = [320.0, 360.0, 411.0];
const _textScales = [1.0, 1.3, 1.5, 2.0];
const _here = GeoPoint(1.5565, 103.641);
const _longStall = 'Warung Nasi Campur Pak Din Yang Sangat Terkenal Di Kampus';

String _inHours(int hours) =>
    DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String();

Listing _listing({String stall = _longStall}) => Listing.fromJson({
  '_id': 'l1',
  'title': 'Nasi Lemak Ayam Goreng Berempah Special With Extra Sambal',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': 10,
  'pickupStart': _inHours(-1),
  'pickupEnd': _inHours(3),
  'allergens': const ['egg', 'milk'],
  'otherAllergens': const <String>[],
  'status': 'active',
  'stallName': stall,
  'pickupAddress': 'Arked Meranti, UTM Skudai',
  'location': [103.6385, 1.559],
});

Future<UserLocationProvider> _located(GeoPoint? point) async {
  final location = UserLocationProvider(
    FakePositionSource(access: LocationAccess.allowed, last: point),
  );
  await location.refreshIfAllowed();
  return location;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  UserLocationProvider? location,
  double width = 411,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
    theme: AppTheme.light,
    builder: (context, page) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: _AndroidText(scale)),
      child: page!,
    ),
    home: Scaffold(body: child),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<FavouritesProvider>(
      create: (_) => FavouritesProvider(
        FavouritesRepository(
          ApiClient(
            client: MockClient((_) async => jsonResponse({'listingIds': []})),
          ),
        ),
      ),
      child: location == null
          ? app
          : ChangeNotifierProvider<UserLocationProvider>.value(
              value: location,
              child: app,
            ),
    ),
  );
}

Widget _card(double width, Listing listing) => Center(
  child: SizedBox(
    width: (width - AppSpacing.md * 2 - AppSpacing.sm) / 2,
    child: Builder(
      builder: (context) => SizedBox(
        height: ListingCard.heightWithActions(context),
        child: ListingCard(
          listing: listing,
          showBadges: true,
          onTap: () {},
          actions: ListingActions(listing: listing),
          actionsWidth: ListingActions.widthOf(context),
        ),
      ),
    ),
  ),
);

Widget _row(double width, Listing listing) => Center(
  child: SizedBox(
    width: width - AppSpacing.md * 2,
    child: SearchResultRow(
      listing: listing,
      onTap: () {},
      actions: ListingActions(listing: listing),
    ),
  ),
);

final _pill = find.byKey(const ValueKey('distance-pill'));

Rect _photoOf(WidgetTester tester) =>
    tester.getRect(find.byType(ListingImage).first);

void main() {
  testWidgets('the distance sits on the photo; the stall line stays plain', (
    tester,
  ) async {
    final location = await _located(_here);
    await _pump(
      tester,
      _card(411, _listing(stall: 'Warung Pak Din')),
      location: location,
    );

    expect(find.text('From Warung Pak Din'), findsOneWidget);
    expect(find.text('390 m'), findsOneWidget);
    final photo = _photoOf(tester);
    final pill = tester.getRect(_pill);
    expect(pill.left, greaterThan(photo.left));
    expect(pill.bottom, lessThanOrEqualTo(photo.bottom));
    expect(pill.left - photo.left, lessThan(photo.width / 2), reason: 'left');
  });

  testWidgets('no distance without the customer location', (tester) async {
    await _pump(tester, _card(411, _listing()));
    expect(_pill, findsNothing);

    await _pump(tester, _card(411, _listing()), location: await _located(null));
    expect(_pill, findsNothing);

    final denied = UserLocationProvider(FakePositionSource(last: _here));
    await denied.refreshIfAllowed();
    await _pump(tester, _row(411, _listing()), location: denied);
    expect(_pill, findsNothing);
  });

  testWidgets('far away reads 20+ km', (tester) async {
    await _pump(
      tester,
      _row(411, _listing()),
      location: await _located(const GeoPoint(37.422, -122.084)),
    );
    expect(find.text('20+ km'), findsOneWidget);
  });

  testWidgets('Food Details says how far the pickup address is', (
    tester,
  ) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => Text(
          distanceAwayFrom(context, const GeoPoint(1.559, 103.6385)) ?? '-',
        ),
      ),
      location: await _located(_here),
    );
    expect(find.text('390 m away'), findsOneWidget);
  });

  for (final (name, build, hasSave) in [
    ('Home cards', _card, true),
    ('Search rows', _row, false),
  ]) {
    testWidgets(
      '$name keep the distance inside the photo, clear of Save, never overflowing',
      (tester) async {
        final location = await _located(_here);
        for (final width in _widths) {
          for (final scale in _textScales) {
            final reason = 'width $width, text x$scale';
            await _pump(
              tester,
              build(width, _listing()),
              location: location,
              width: width,
              scale: scale,
            );
            final error = tester.takeException();
            if (error != null) fail('$reason: $error');
            if (_pill.evaluate().isEmpty) continue;

            final photo = _photoOf(tester);
            final pill = tester.getRect(_pill);
            expect(pill.left, greaterThanOrEqualTo(photo.left), reason: reason);
            expect(
              pill.right,
              lessThanOrEqualTo(photo.right + 0.01),
              reason: reason,
            );
            expect(
              pill.bottom,
              lessThanOrEqualTo(photo.bottom + 0.01),
              reason: reason,
            );
            if (hasSave) {
              final save = tester.getRect(find.textContaining('Save '));
              expect(
                pill.right <= save.left + 0.01 || pill.bottom <= save.top,
                isTrue,
                reason: 'beside or above Save, $reason',
              );
            }
          }
        }
        // At normal text on every phone width the distance shows.
        for (final width in _widths) {
          await _pump(
            tester,
            build(width, _listing()),
            location: location,
            width: width,
          );
          expect(_pill, findsOneWidget, reason: 'width $width');
        }
      },
    );
  }
}
