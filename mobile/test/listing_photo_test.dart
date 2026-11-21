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
import 'package:savespoon/features/listings/presentation/pages/frame_photo_page.dart';
import 'package:savespoon/features/profile/data/photo_picker.dart';

import 'helpers.dart';

final DateTime _today = DateTime.now();
final DateTime _now = DateTime(_today.year, _today.month, _today.day, 12);
final DateTime _start = DateTime(_today.year, _today.month, _today.day, 11);
final DateTime _end = DateTime(_today.year, _today.month, _today.day, 14);

const _photo = {
  'imageUrl': 'https://example.com/full.jpg',
  'imageThumbUrl': 'https://example.com/thumb.jpg',
  'imageOriginalUrl': 'https://example.com/original.jpg',
  'imageCrop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
};

Map<String, dynamic> _json({String id = 'l1', bool withPhoto = false}) => {
  '_id': id,
  'title': 'Nasi Lemak',
  'description': 'With sambal',
  'category': 'Rice',
  'isHalal': true,
  'originalPrice': 8,
  'discountedPrice': 4.5,
  'quantityAvailable': 5,
  'soldCount': 0,
  'pickupStart': _start.toUtc().toIso8601String(),
  'pickupEnd': _end.toUtc().toIso8601String(),
  'allergens': <String>[],
  'otherAllergens': <String>[],
  'status': 'active',
  if (withPhoto) ..._photo,
};

class _Picker implements PhotoPicker {
  PhotoSource? source;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    this.source = source;
    return const PickedPhoto(bytes: [1, 2, 3], filename: 'food.jpg');
  }
}

// A wide 16:9 picture.
Future<Size?> _wide(BuildContext context, ImageProvider image) async =>
    const Size(1600, 900);

class _Server {
  final List<String> calls = [];
  String? photoBody;
  int photoStatus = 200;

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    calls.add('${request.method} $path');
    if (request.method == 'POST' && path == '/api/listings') {
      return jsonResponse({'listing': _json(id: 'new')}, 201);
    }
    if (request.method == 'GET' && path == '/api/listings/mine/l1') {
      return jsonResponse({
        'listing': _json(withPhoto: true),
        'pastSold': 0,
        'activeOrderCount': 0,
      });
    }
    if (request.method == 'GET' && path == '/api/listings/mine') {
      return jsonResponse({'listings': <Object>[]});
    }
    if (path.endsWith('/photo')) {
      photoBody = request.body;
      if (photoStatus != 200) {
        return jsonResponse({
          'error': "Our server couldn't upload the photo right now.",
        }, photoStatus);
      }
      final id = path.split('/')[3];
      final removing = request.method == 'DELETE';
      return jsonResponse({'listing': _json(id: id, withPhoto: !removing)});
    }
    return jsonResponse({'error': 'Not found'}, 404);
  }
}

Future<List<Object?>> _pump(
  WidgetTester tester,
  _Server server, {
  Listing? editing,
  _Picker? picker,
}) async {
  tester.view.physicalSize = const Size(1200, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <Object?>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                results.add(await context.push<Listing>('/form')),
            child: const Text('Open'),
          ),
        ),
      ),
      GoRoute(
        path: '/form',
        builder: (context, state) => AddListingPage(
          editing: editing,
          now: () => _now,
          photoPicker: picker ?? _Picker(),
          sizer: _wide,
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
  return results;
}

Future<void> _addPhoto(WidgetTester tester) async {
  await tester.tap(find.text('Upload Image Here'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Take a Photo'));
  await tester.pumpAndSettle();
  expect(find.byType(FramePhotoPage), findsOneWidget);
  await tester.tap(find.text('Confirm'));
  await tester.pumpAndSettle();
}

Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(find.bySemanticsLabel('Item name'), 'Kuih Lapis');
  await tester.enterText(find.bySemanticsLabel('Original (RM)'), '5');
  await tester.enterText(find.bySemanticsLabel('Discounted (RM)'), '3');
  await tester.enterText(find.bySemanticsLabel('Stock'), '4');
  await tester.tap(find.text('Desserts'));
  await tester.tap(find.text('Yes'));
  await tester.pump();
}

double _field(String body, String name) => double.parse(
  RegExp('name="$name"\\r?\\n\\r?\\n([^\\r\\n]+)').firstMatch(body)!.group(1)!,
);

FilledButton _saveChanges(WidgetTester tester) => tester.widget<FilledButton>(
  find.ancestor(
    of: find.text('Save Changes'),
    matching: find.byType(FilledButton),
  ),
);

void main() {
  testWidgets('Add a Listing shows the Upload Image Here box', (tester) async {
    await _pump(tester, _Server());
    expect(find.text('Upload Image Here'), findsOneWidget);
    expect(find.text('Remove Photo'), findsNothing);
  });

  testWidgets('a framed photo uploads in 4:3 after the listing is saved', (
    tester,
  ) async {
    final server = _Server();
    final picker = _Picker();
    final results = await _pump(tester, server, picker: picker);

    await _addPhoto(tester);
    expect(picker.source, PhotoSource.camera);
    expect(find.byKey(const ValueKey('listing-photo-preview')), findsOneWidget);
    expect(find.text('Change Photo'), findsOneWidget);
    expect(find.text('Adjust Framing'), findsOneWidget);
    expect(find.text('Remove Photo'), findsOneWidget);

    await _fillForm(tester);
    await tester.ensureVisible(find.text('Save Listing'));
    await tester.tap(find.text('Save Listing'));
    await tester.pumpAndSettle();

    expect(server.calls, ['POST /api/listings', 'PUT /api/listings/new/photo']);
    final body = server.photoBody!;
    expect(body, contains('filename="food.jpg"'));
    final ratio =
        _field(body, 'cropWidth') * 1600 / (_field(body, 'cropHeight') * 900);
    expect(ratio, closeTo(4 / 3, 0.01));
    final saved = results.single! as Listing;
    expect(saved.imageUrl, 'https://example.com/full.jpg');
  });

  testWidgets('a failed upload keeps the listing and says to re-add it', (
    tester,
  ) async {
    final server = _Server()..photoStatus = 503;
    final results = await _pump(tester, server);

    await _addPhoto(tester);
    await _fillForm(tester);
    await tester.ensureVisible(find.text('Save Listing'));
    await tester.tap(find.text('Save Listing'));
    await tester.pumpAndSettle();

    // The form closes and the message shows over the page it returns to.
    expect(find.byKey(const ValueKey('photo-not-saved')), findsOneWidget);
    expect(
      find.text(
        "Nasi Lemak saved, but our server couldn't upload the photo. "
        'Please re-add it from Edit Listing later.',
      ),
      findsOneWidget,
    );
    final saved = results.single! as Listing;
    expect(saved.id, 'new');
    expect(saved.imageUrl, isNull);
  });

  testWidgets('removing a photo picked before saving uploads nothing', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);

    await _addPhoto(tester);
    await tester.tap(find.text('Remove Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Upload Image Here'), findsOneWidget);

    await _fillForm(tester);
    await tester.ensureVisible(find.text('Save Listing'));
    await tester.tap(find.text('Save Listing'));
    await tester.pumpAndSettle();
    expect(server.calls, ['POST /api/listings']);
  });

  group('Edit Listing', () {
    final editing = Listing.fromJson(_json(withPhoto: true));

    testWidgets('shows the saved photo, and removing it enables Save', (
      tester,
    ) async {
      final server = _Server();
      final results = await _pump(tester, server, editing: editing);

      expect(find.text('Upload Image Here'), findsNothing);
      expect(find.text('Adjust Framing'), findsOneWidget);
      expect(_saveChanges(tester).onPressed, isNull);

      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();
      expect(find.text('Upload Image Here'), findsOneWidget);
      expect(_saveChanges(tester).onPressed, isNotNull);

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Only the photo changed, so the details aren't sent again.
      expect(server.calls.where((call) => call.startsWith('PATCH')), isEmpty);
      expect(server.calls, contains('DELETE /api/listings/l1/photo'));
      expect((results.single! as Listing).imageUrl, isNull);
    });

    testWidgets('re-framing sends the new framing without uploading', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, editing: editing);

      await tester.tap(find.text('Adjust Framing'));
      await tester.pumpAndSettle();
      final framer = find.byType(FramePhotoPage);
      expect(framer, findsOneWidget);
      // Zoom in so the framing differs from the saved one.
      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(_saveChanges(tester).onPressed, isNotNull);
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(server.calls, contains('PATCH /api/listings/l1/photo'));
      expect(server.calls, isNot(contains('PUT /api/listings/l1/photo')));
      final crop = (jsonDecode(server.photoBody!) as Map)['crop'] as Map;
      expect(crop['width'] as num, lessThan(1));
    });

    testWidgets('a photo-only save that fails still closes, with a note', (
      tester,
    ) async {
      final server = _Server()..photoStatus = 503;
      final results = await _pump(tester, server, editing: editing);

      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Closed with nothing saved, so the listing page won't say "Changes saved."
      expect(results, [null]);
      expect(find.text('Save Changes'), findsNothing);
      expect(
        find.text(
          "Our server couldn't upload the photo. Please try again later "
          'from Edit Listing.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a photo change asks before leaving', (tester) async {
      await _pump(tester, _Server(), editing: editing);
      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
    });
  });
}
