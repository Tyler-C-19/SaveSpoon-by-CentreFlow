import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/cart/domain/cart.dart';
import 'package:savespoon/features/listings/domain/listing.dart';
import 'package:savespoon/features/orders/domain/order.dart';
import 'package:savespoon/features/listings/presentation/pages/photo_view_page.dart';
import 'package:savespoon/features/listings/presentation/widgets/food_thumbnail.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_card.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_image.dart';
import 'package:savespoon/features/profile/domain/photo_crop.dart';

Map<String, dynamic> _json({Map<String, dynamic> extra = const {}}) {
  final now = DateTime.now();
  return {
    '_id': 'l1',
    'title': 'Nasi Lemak',
    'category': 'Rice',
    'isHalal': true,
    'originalPrice': 8,
    'discountedPrice': 4.5,
    'quantityAvailable': 8,
    'pickupStart': now
        .subtract(const Duration(hours: 1))
        .toUtc()
        .toIso8601String(),
    'pickupEnd': now.add(const Duration(hours: 3)).toUtc().toIso8601String(),
    'allergens': <String>[],
    'status': 'active',
    ...extra,
  };
}

Future<void> _show(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  test(
    'a listing reads both photo sizes, and cards prefer the smaller one',
    () {
      final listing = Listing.fromJson(
        _json(
          extra: {
            'imageUrl': 'https://cdn/full.jpg',
            'imageThumbUrl': 'https://cdn/thumb.jpg',
            'imageOriginalUrl': 'https://cdn/original.jpg',
            'imageCrop': {'x': 0, 'y': 0.1, 'width': 1, 'height': 0.8},
          },
        ),
      );
      expect(listing.cardImageUrl, 'https://cdn/thumb.jpg');
      expect(listing.canReframePhoto, isTrue);
      expect(Listing.fromJson(_json()).cardImageUrl, isNull);
    },
  );

  test('a cart item reads its thumbnail', () {
    final item = CartItem.fromJson({
      'listingId': 'l1',
      'itemName': 'Nasi Lemak',
      'stallName': 'Warung',
      'quantity': 1,
      'unitPrice': 4.5,
      'lineTotal': 4.5,
      'available': true,
      'notices': <String>[],
      'imageThumbUrl': 'https://cdn/thumb.jpg',
    });
    expect(item.imageThumbUrl, 'https://cdn/thumb.jpg');
  });

  testWidgets('no photo shows the category icon', (tester) async {
    await _show(
      tester,
      const SizedBox(
        width: 200,
        height: 150,
        child: ListingImage(url: null, category: 'Rice'),
      ),
    );
    expect(find.byKey(const ValueKey('listing-photo')), findsNothing);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('a photo loads over the icon, which stays if it fails', (
    tester,
  ) async {
    await _show(
      tester,
      const SizedBox(
        width: 200,
        height: 150,
        child: ListingImage(url: 'https://cdn/thumb.jpg', category: 'Rice'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-photo')), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('cards and thumbnails use the small photo', (tester) async {
    final listing = Listing.fromJson(
      _json(
        extra: {
          'imageUrl': 'https://cdn/full.jpg',
          'imageThumbUrl': 'https://cdn/thumb.jpg',
        },
      ),
    );
    await _show(
      tester,
      Row(
        children: [
          SizedBox(
            width: 200,
            height: 260,
            child: ListingCard(listing: listing),
          ),
          const FoodThumbnail(
            category: 'Rice',
            imageUrl: 'https://cdn/thumb.jpg',
          ),
        ],
      ),
    );
    final urls = [
      for (final image in tester.widgetList<Image>(
        find.byKey(const ValueKey('listing-photo')),
      ))
        (image.image as NetworkImage).url,
    ];
    expect(urls, ['https://cdn/thumb.jpg', 'https://cdn/thumb.jpg']);
  });

  testWidgets('the full-screen view shows the photo with pinch zoom', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                openPhotoView(context, 'https://cdn/full.jpg', 'Nasi Lemak'),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Nasi Lemak'), findsOneWidget);
    final image = tester.widget<Image>(
      find.byKey(const ValueKey('full-photo')),
    );
    expect((image.image as NetworkImage).url, 'https://cdn/full.jpg');
  });

  testWidgets('unlisted photos get a grey wash, not black and white', (
    tester,
  ) async {
    await _show(
      tester,
      const SizedBox(
        width: 200,
        height: 150,
        child: ListingImage(
          url: 'https://cdn/thumb.jpg',
          category: 'Rice',
          greyed: true,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('listing-photo-grey')), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets(
    'a large photo shows the card photo and a spinner while loading',
    (tester) async {
      await _show(
        tester,
        const SizedBox(
          width: 300,
          height: 200,
          child: ListingImage(
            url: 'https://cdn/full.jpg',
            placeholderUrl: 'https://cdn/thumb.jpg',
            category: 'Rice',
            showLoading: true,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('listing-photo-early')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  test('an order reads the photo copied when it was placed', () {
    final order = Order.fromJson({
      '_id': 'o1',
      'listing': 'l1',
      'itemName': 'Nasi Lemak',
      'stallName': 'Warung',
      'quantity': 1,
      'unitPrice': 4.5,
      'totalPrice': 4.5,
      'status': 'pending',
      'pickupStart': DateTime.now().toUtc().toIso8601String(),
      'pickupEnd': DateTime.now().toUtc().toIso8601String(),
      'imageThumbUrl': 'https://cdn/thumb.jpg',
    });
    expect(order.imageThumbUrl, 'https://cdn/thumb.jpg');
  });

  testWidgets('a photo gets the green border; no photo, no border', (
    tester,
  ) async {
    await _show(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhotoBorder(
            show: true,
            radius: 16,
            child: SizedBox(width: 80, height: 60),
          ),
          PhotoBorder(
            show: false,
            radius: 16,
            child: SizedBox(width: 80, height: 60),
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('photo-border')), findsOneWidget);
  });

  testWidgets('card photos show a small spinner while they download', (
    tester,
  ) async {
    await _show(
      tester,
      const SizedBox(
        width: 200,
        height: 150,
        child: ListingImage(url: 'https://cdn/thumb.jpg', category: 'Rice'),
      ),
    );
    expect(find.byKey(const ValueKey('listing-photo-loading')), findsOneWidget);
  });

  group('4:3 framing maths', () {
    const aspect = 4 / 3;

    test('a wide picture starts centred, filling the frame height', () {
      final crop = PicFrame.centred(
        const Size(1600, 900),
        400,
        aspect: aspect,
      ).toCrop();
      expect(crop.height, closeTo(1, 1e-9));
      expect(crop.width, closeTo(0.75, 1e-9));
      expect(crop.x, closeTo(0.125, 1e-9));
    });

    test('a tall picture starts centred, filling the frame width', () {
      final crop = PicFrame.centred(
        const Size(900, 1600),
        400,
        aspect: aspect,
      ).toCrop();
      expect(crop.width, closeTo(1, 1e-9));
      expect(crop.width * 900 / (crop.height * 1600), closeTo(aspect, 1e-9));
    });

    test('a saved framing opens where it was left', () {
      const saved = PhotoCrop(
        x: 0.1,
        y: 0.2,
        width: 0.5,
        height: 0.5 * 1600 / 900 / aspect,
      );
      final crop = PicFrame.fromCrop(
        saved,
        const Size(1600, 900),
        400,
        aspect: aspect,
      ).toCrop();
      expect(crop.sameAs(saved), isTrue);
    });

    test('the square frame is unchanged for profile pictures', () {
      final crop = PicFrame.centred(const Size(1600, 900), 300).toCrop();
      expect(crop.height, closeTo(1, 1e-9));
      expect(crop.width, closeTo(900 / 1600, 1e-9));
    });
  });
}
