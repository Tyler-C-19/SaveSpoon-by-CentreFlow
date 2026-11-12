import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/auth/data/auth_repository.dart';
import 'package:savespoon/features/auth/presentation/pages/login_page.dart';
import 'package:savespoon/features/auth/presentation/providers/auth_provider.dart';
import 'package:savespoon/features/profile/data/photo_picker.dart';
import 'package:savespoon/features/profile/data/profile_repository.dart';
import 'package:savespoon/features/profile/domain/photo_crop.dart';
import 'package:savespoon/features/profile/domain/user_profile.dart';
import 'package:savespoon/features/profile/presentation/pages/edit_details_page.dart';
import 'package:savespoon/features/profile/presentation/pages/edit_picture_page.dart';
import 'package:savespoon/features/profile/presentation/widgets/picture_framer.dart';
import 'package:savespoon/features/profile/presentation/widgets/delete_account_flow.dart';
import 'package:savespoon/features/profile/presentation/widgets/location_change_dialog.dart';
import 'package:savespoon/features/profile/presentation/widgets/profile_avatar.dart';
import 'package:savespoon/features/seller_profile/data/location_service.dart';
import 'package:savespoon/features/seller_profile/data/vendor_repository.dart';
import 'package:savespoon/features/seller_profile/domain/geo_point.dart';
import 'package:savespoon/features/seller_profile/domain/vendor_profile.dart';
import 'package:savespoon/features/seller_profile/presentation/pages/vendor_setup_page.dart';

import 'helpers.dart';

Future<void> tapButton(WidgetTester tester, String label) async {
  // Lets buttons pick up the latest typing first.
  await tester.pump();
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  await tester.ensureVisible(button.last);
  await tester.tap(button.last);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

const vendorJson = {
  'stallName': 'Warung Test',
  'phone': '012-3456789',
  'address': 'Cafeteria A, UTM Skudai',
  'description': 'Rice and noodles',
  'location': {
    'type': 'Point',
    'coordinates': [103.6385, 1.559],
  },
  'placeId': 'place-1',
};

// A small stand-in for the profile endpoints.
class FakeServer {
  FakeServer({
    this.role = 'customer',
    this.hasPassword = true,
    this.isGoogleLinked = false,
    this.summary = const {
      'listingCount': 0,
      'activeListingCount': 0,
      'activeOrderCount': 0,
    },
  });

  final String role;
  final bool hasPassword;
  final bool isGoogleLinked;
  bool photoUploads = true;
  String? lockedUntil;
  Map<String, dynamic> photo = {};
  Map<String, dynamic> summary;
  final List<http.Request> requests = [];
  late Map<String, dynamic> user = {
    ...userJson,
    'role': role,
    'phone': '012-3456789',
    'hasVendorProfile': role == 'vendor',
  };

  Map<String, dynamic> get profile => {
    ...user,
    'hasPassword': hasPassword,
    'isGoogleLinked': isGoogleLinked,
    'lockedUntil': ?lockedUntil,
    ...photo,
    if (role == 'vendor') 'vendor': vendorJson,
  };

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    final isJson = request.headers['content-type']?.contains('json') ?? false;
    final body = isJson && request.body.isNotEmpty
        ? jsonDecode(request.body)
        : <String, dynamic>{};

    if (path == '/api/auth/me') return jsonResponse({'user': user});
    if (path == '/api/users/me/summary') return jsonResponse(summary);
    if (path == '/api/users/me' && request.method == 'GET') {
      return jsonResponse({'user': profile});
    }
    if (path == '/api/users/me' && request.method == 'PATCH') {
      user = {...user, ...body as Map<String, dynamic>};
      return jsonResponse({'user': profile});
    }
    if (path == '/api/users/me' && request.method == 'DELETE') {
      if (body['password'] == 'wrongpass1') {
        return jsonResponse({
          'error': 'Your password is incorrect. 2 tries left.',
          'code': 'WRONG_PASSWORD',
        }, 400);
      }
      if (body['password'] == 'lockedout1') {
        return jsonResponse({
          'error': 'Too many wrong tries. Try again in 15 minutes.',
          'code': 'TOO_MANY_TRIES',
        }, 429);
      }
      return jsonResponse({'message': 'Your account has been deleted.'});
    }
    if (path == '/api/users/me/photo' &&
        request.method == 'PUT' &&
        photoUploads) {
      photo = {
        'photoUrl': 'https://example.com/framed.jpg',
        'photoOriginalUrl': 'https://example.com/original.jpg',
        'photoCrop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      };
      return jsonResponse({'user': profile});
    }
    if (path == '/api/users/me/photo' && request.method == 'PATCH') {
      photo = {...photo, 'photoCrop': body['crop']};
      return jsonResponse({'user': profile});
    }
    if (path == '/api/users/me/email' && request.method == 'DELETE') {
      return jsonResponse({'user': profile});
    }
    if (path == '/api/vendors/me' && request.method == 'PUT') {
      return jsonResponse({'vendor': vendorJson, 'listingsUpdated': 3});
    }
    if (path == '/api/users/me/password') {
      if (body['currentPassword'] != 'oldpass123') {
        return jsonResponse({
          'error': 'Your current password is incorrect.',
          'code': 'WRONG_PASSWORD',
        }, 400);
      }
      return jsonResponse({
        'token': 'new-token',
        'message': 'Password changed.',
      });
    }
    if (path == '/api/users/me/email' &&
        request.method == 'POST' &&
        body['currentPassword'] == 'lockedout1') {
      lockedUntil = DateTime.now()
          .add(const Duration(minutes: 15))
          .toIso8601String();
      return jsonResponse({
        'error': 'Too many wrong tries. Try again in 15 minutes.',
        'code': 'TOO_MANY_TRIES',
      }, 429);
    }
    if (path == '/api/users/me/email' && request.method == 'POST') {
      return jsonResponse({
        'pendingEmail': body['newEmail'],
        'emailSent': true,
      });
    }
    if (path == '/api/users/me/email/verify') {
      if (body['code'] != '123456') {
        return jsonResponse({'error': 'That code is wrong.'}, 400);
      }
      user = {...user, 'email': 'new@example.com'};
      return jsonResponse({'user': profile});
    }
    return jsonResponse({'error': 'Not found'}, 404);
  }

  http.Request? last(String method, String path) => requests
      .lastWhere(
        (r) => r.method == method && r.url.path == path,
        orElse: () => http.Request('NONE', Uri()),
      )
      .let((r) => r.method == 'NONE' ? null : r);
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

Future<FakeTokenStorage> openProfile(
  WidgetTester tester,
  FakeServer server,
) async {
  final storage = FakeTokenStorage(
    token: 'saved',
    userJson: jsonEncode(server.user),
  );
  await startApp(tester, storage: storage, onRequest: server.handle);
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
  return storage;
}

const frameChoice = PhotoCrop(x: 0.1, y: 0, width: 0.75, height: 1);

Future<Size?> fakeSize(BuildContext context, ImageProvider image) async =>
    const Size(1000, 800);

const savedPhoto = {
  'photoUrl': 'https://example.com/framed.jpg',
  'photoOriginalUrl': 'https://example.com/original.jpg',
  'photoCrop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
};

class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker(this.photo);

  final PickedPhoto? photo;
  PhotoSource? source;

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    this.source = source;
    return photo;
  }
}

class NoLocation implements LocationService {
  @override
  Future<GeoPoint?> currentLocation() async => null;

  @override
  Future<String?> addressAt(GeoPoint point) async => 'Arked Meranti, Skudai';
}

Widget fakeMap(
  BuildContext context,
  GeoPoint target,
  GeoPoint? pin,
  ValueChanged<GeoPoint> onTap,
) => TextButton(
  onPressed: () => onTap(const GeoPoint(1.56, 103.64)),
  child: const Text('map'),
);

class Result<T> {
  T? value;
}

// Like pumpAlone, and also keeps what the page closes with.
Future<Result<Object?>> pumpAloneForResult(
  WidgetTester tester,
  FakeServer server,
  Widget page,
) async {
  final result = Result<Object?>();
  await pumpAlone(
    tester,
    server,
    page,
    onClosed: (value) => result.value = value,
  );
  return result;
}

// Builds a page with the real repositories over a fake server.
Future<AuthProvider> pumpAlone(
  WidgetTester tester,
  FakeServer server,
  Widget page, {
  void Function(Object?)? onClosed,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final storage = FakeTokenStorage(
    token: 'saved',
    userJson: jsonEncode(server.user),
  );
  final api = ApiClient(
    client: MockClient(server.handle),
    tokenReader: storage.readToken,
  );
  final auth = AuthProvider()
    ..attach(AuthRepository(api: api, storage: storage), FakeGoogleAuth());
  await auth.restoreSession();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        Provider<VendorRepository>.value(value: VendorRepository(api)),
        Provider<ProfileRepository>.value(value: ProfileRepository(api)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final value = await Navigator.push(
                  context,
                  MaterialPageRoute<Object?>(builder: (_) => page),
                );
                onClosed?.call(value);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  group('AC1 profile tab', () {
    testWidgets('shows account details, password and the buttons', (
      tester,
    ) async {
      await openProfile(tester, FakeServer());

      expect(find.text('Test Person'), findsWidgets);
      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('person@example.com'), findsOneWidget);
      expect(find.text('012-3456789'), findsOneWidget);
      expect(find.text('Change Password'), findsOneWidget);
      expect(find.text('Profile'), findsWidgets);
      expect(find.text('Log Out'), findsOneWidget);
      expect(find.text('Delete Account'), findsOneWidget);
      expect(find.text('Vendor Details'), findsNothing);
    });

    testWidgets('a Google-only account shows it has no password', (
      tester,
    ) async {
      await openProfile(
        tester,
        FakeServer(hasPassword: false, isGoogleLinked: true),
      );

      expect(find.text('Signed in with Google, no password.'), findsOneWidget);
      expect(find.text('Change Password'), findsNothing);
      expect(find.textContaining('linked to Google'), findsOneWidget);
    });

    testWidgets('a vendor also sees the business section', (tester) async {
      await openProfile(tester, FakeServer(role: 'vendor'));

      expect(find.text('Vendor'), findsOneWidget);
      expect(find.text('Vendor Details'), findsOneWidget);
      expect(find.text('Vendor name'), findsOneWidget);
      expect(find.text('Warung Test'), findsOneWidget);
      expect(find.text('Cafeteria A, UTM Skudai'), findsOneWidget);
      expect(find.text('Rice and noodles'), findsOneWidget);
    });

    testWidgets('Log out returns to login', (tester) async {
      final storage = await openProfile(tester, FakeServer());
      await tapButton(tester, 'Log Out');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(storage.token, isNull);
    });
  });

  group('AC2 edit details and photo', () {
    testWidgets('saves name and phone and updates the profile', (tester) async {
      final server = FakeServer();
      final storage = await openProfile(tester, server);

      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Full name'), '  New Name ');
      await tester.enterText(field('Phone number'), '019-8765432');
      await tapButton(tester, 'Save Changes');

      final sent = jsonDecode(server.last('PATCH', '/api/users/me')!.body);
      expect(sent, {'name': 'New Name', 'phone': '019-8765432'});
      expect(find.text('Edit Account Details'), findsNothing);
      expect(find.text('New Name'), findsOneWidget);
      expect(find.text('Account details updated.'), findsOneWidget);
      expect(jsonDecode(storage.userJson!)['name'], 'New Name');
    });

    testWidgets('the banner can be dismissed', (tester) async {
      await openProfile(tester, FakeServer());
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Phone number'), '019-8765432');
      await tapButton(tester, 'Save Changes');

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Account details updated.'), findsNothing);
    });

    testWidgets('the banner goes when leaving My Profile', (tester) async {
      await openProfile(tester, FakeServer());
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Phone number'), '019-8765432');
      await tapButton(tester, 'Save Changes');
      expect(find.text('Account details updated.'), findsOneWidget);

      // Another tab, then back.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Account details updated.'), findsNothing);

      // Opening a page from My Profile clears it too.
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Phone number'), '012-3456789');
      await tapButton(tester, 'Save Changes');
      expect(find.text('Account details updated.'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Account details updated.'), findsNothing);
    });

    testWidgets('Save Changes is off until something changes', (tester) async {
      final server = FakeServer();
      await openProfile(tester, server);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();

      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save Changes'),
      );
      expect(save.onPressed, isNull);

      await tester.enterText(field('Phone number'), '019-8765432');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save Changes'),
            )
            .onPressed,
        isNotNull,
      );

      // Changing it back means nothing to save again.
      await tester.enterText(field('Phone number'), '012-3456789');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save Changes'),
            )
            .onPressed,
        isNull,
      );
      expect(server.last('PATCH', '/api/users/me'), isNull);
    });

    testWidgets('leaving with unsaved changes asks first', (tester) async {
      final server = FakeServer();
      await openProfile(tester, server);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Full name'), 'Other Name');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tapButton(tester, 'Keep Editing');
      expect(find.text('Edit Account Details'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Discard');
      expect(find.text('Edit Account Details'), findsNothing);
      expect(server.last('PATCH', '/api/users/me'), isNull);
    });

    testWidgets('invalid input saves nothing', (tester) async {
      final server = FakeServer();
      await openProfile(tester, server);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();

      await tester.enterText(field('Full name'), ' ');
      await tester.enterText(field('Phone number'), 'abc');
      await tapButton(tester, 'Save Changes');

      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Enter a valid phone number.'), findsOneWidget);
      expect(server.last('PATCH', '/api/users/me'), isNull);
    });

    testWidgets('an added pic gets a green ring', (tester) async {
      final server = FakeServer()
        ..photo = {'photoUrl': 'https://example.com/framed.jpg'};
      await openProfile(tester, server);

      expect(
        find.ancestor(
          of: find.byType(CircleAvatar),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                (w.decoration as BoxDecoration?)?.shape == BoxShape.circle,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('leaving without changes shows no banner', (tester) async {
      final server = FakeServer();
      await openProfile(tester, server);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      final page = tester.widget<EditDetailsPage>(find.byType(EditDetailsPage));
      expect(page.photoPicker, isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Dismiss'), findsNothing);
    });
  });

  group('AC2 edit profile picture', () {
    Future<Result<Object?>> openPicture(
      WidgetTester tester,
      FakeServer server, {
      PhotoPicker? picker,
    }) => pumpAloneForResult(
      tester,
      server,
      EditPicturePage(
        profile: UserProfile.fromJson(server.profile),
        photoPicker:
            picker ??
            FakePhotoPicker(
              const PickedPhoto(bytes: [1, 2, 3], filename: 'me.jpg'),
            ),
        sizer: fakeSize,
      ),
    );

    FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );

    testWidgets('nothing to confirm or undo until something changes', (
      tester,
    ) async {
      await openPicture(tester, FakeServer());

      expect(find.text('No profile picture'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Undo'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('a new picture is previewed and only saved on Confirm', (
      tester,
    ) async {
      final server = FakeServer();
      final picker = FakePhotoPicker(
        const PickedPhoto(bytes: [1, 2, 3], filename: 'me.jpg'),
      );
      final closed = await openPicture(tester, server, picker: picker);

      await tapButton(tester, 'Choose from Gallery');

      expect(picker.source, PhotoSource.gallery);
      expect(find.byType(PictureFramer), findsOneWidget);
      expect(find.byType(FramedImage), findsOneWidget);
      expect(find.text('Preview'), findsOneWidget);
      expect(server.last('PUT', '/api/users/me/photo'), isNull);

      await tapButton(tester, 'Confirm');

      final upload = server.last('PUT', '/api/users/me/photo')!;
      expect(upload.headers['content-type'], startsWith('multipart/form-data'));
      // A 1000 x 800 picture starts centred: the middle 800 x 800.
      expect(
        utf8.decode(upload.bodyBytes, allowMalformed: true),
        allOf(
          contains('filename="me.jpg"'),
          contains('name="cropX"\r\n\r\n0.1'),
          contains('name="cropWidth"\r\n\r\n0.8'),
        ),
      );
      expect(closed.value, isA<UserProfile>());
      expect(find.text('Edit Profile Picture'), findsNothing);
    });

    testWidgets('Undo puts back how it was when the page opened', (
      tester,
    ) async {
      await openPicture(tester, FakeServer());

      await tapButton(tester, 'Take a Photo');
      expect(find.byType(FramedImage), findsOneWidget);
      await tapButton(tester, 'Undo');

      expect(find.text('No profile picture'), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);
    });

    testWidgets('the saved picture can be removed, or the removal undone', (
      tester,
    ) async {
      final server = FakeServer()..photo = savedPhoto;
      await openPicture(tester, server);

      await tapButton(tester, 'Remove Picture');
      expect(find.text('No profile picture'), findsOneWidget);
      await tapButton(tester, 'Undo');
      expect(find.byType(PictureFramer), findsOneWidget);
      expect(confirm(tester).onPressed, isNull);

      await tapButton(tester, 'Remove Picture');
      await tapButton(tester, 'Confirm');
      expect(server.last('DELETE', '/api/users/me/photo'), isNotNull);
    });

    testWidgets('the saved picture is framed again without a new upload', (
      tester,
    ) async {
      final server = FakeServer()..photo = savedPhoto;
      await openPicture(tester, server);
      expect(confirm(tester).onPressed, isNull);

      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Confirm');

      final sent = jsonDecode(
        server.last('PATCH', '/api/users/me/photo')!.body,
      );
      expect(sent['crop']['width'], lessThan(0.8));
      expect(server.last('PUT', '/api/users/me/photo'), isNull);
    });

    testWidgets('an older picture without its original cannot be moved', (
      tester,
    ) async {
      final server = FakeServer()
        ..photo = {'photoUrl': 'https://example.com/framed.jpg'};
      await openPicture(tester, server);

      expect(
        find.text('Choose a new picture to change the framing.'),
        findsOneWidget,
      );
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('a failed upload shows the message and stays open', (
      tester,
    ) async {
      final server = FakeServer()..photoUploads = false;
      await openPicture(tester, server);

      await tapButton(tester, 'Choose from Gallery');
      await tapButton(tester, 'Confirm');

      expect(find.text('Not found'), findsOneWidget);
      expect(find.text('Edit Profile Picture'), findsOneWidget);
    });

    testWidgets('leaving with a new picture asks first', (tester) async {
      final server = FakeServer();
      await openPicture(tester, server);
      await tapButton(tester, 'Choose from Gallery');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tapButton(tester, 'Discard');
      expect(find.text('open'), findsOneWidget);
      expect(server.last('PUT', '/api/users/me/photo'), isNull);
    });

    testWidgets('a confirmed picture shows on Edit Account Details', (
      tester,
    ) async {
      final server = FakeServer();
      final closed = await pumpAloneForResult(
        tester,
        server,
        EditDetailsPage(
          photoPicker: FakePhotoPicker(
            const PickedPhoto(bytes: [1, 2, 3], filename: 'me.jpg'),
          ),
          sizer: fakeSize,
        ),
      );

      await tapButton(tester, 'Edit Profile Picture');
      await tapButton(tester, 'Choose from Gallery');
      await tapButton(tester, 'Confirm');

      // Back on Edit Account Details, with no "Not saved yet" note.
      expect(find.text('Edit Account Details'), findsOneWidget);
      expect(find.text('Not saved yet'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final change = closed.value as ProfileChange;
      expect(change.message, 'Profile picture updated.');
      expect(change.profile?.photoUrl, 'https://example.com/framed.jpg');
    });
  });

  group('AC3 change email', () {
    testWidgets('sends a code, then the code changes the email', (
      tester,
    ) async {
      final server = FakeServer();
      final storage = await openProfile(tester, server);

      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      expect(field('Current password'), findsNothing);
      await tester.enterText(field('Email'), 'New@Example.com');
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'oldpass123');
      await tapButton(tester, 'Save and Send Code');

      expect(jsonDecode(server.last('POST', '/api/users/me/email')!.body), {
        'newEmail': 'new@example.com',
        'currentPassword': 'oldpass123',
      });
      expect(
        find.textContaining('Code sent to new@example.com'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).last, '123456');
      await tapButton(tester, 'Verify');

      expect(find.text('new@example.com'), findsOneWidget);
      expect(
        find.text(
          'Account details updated. Your email is now new@example.com.',
        ),
        findsOneWidget,
      );
      expect(jsonDecode(storage.userJson!)['email'], 'new@example.com');
    });

    testWidgets('editing the email explains the change and can be undone', (
      tester,
    ) async {
      await openProfile(tester, FakeServer());
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();

      await tester.enterText(field('Email'), 'new@example.com');
      await tester.pumpAndSettle();
      expect(
        find.textContaining("We'll email a code to the new address"),
        findsOneWidget,
      );

      await tapButton(tester, 'Keep Current Email');
      expect(find.text('person@example.com'), findsOneWidget);
      expect(field('Current password'), findsNothing);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('keeping the current email at the code step cancels it', (
      tester,
    ) async {
      final server = FakeServer();
      await openProfile(tester, server);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email'), 'new@example.com');
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'oldpass123');
      await tapButton(tester, 'Save and Send Code');

      await tapButton(tester, 'Keep My Current Email');

      expect(server.last('DELETE', '/api/users/me/email'), isNotNull);
      expect(field('Email'), findsOneWidget);
      expect(find.text('person@example.com'), findsOneWidget);
    });

    testWidgets('the code step stays in the email box with the fields locked', (
      tester,
    ) async {
      final server = FakeServer();
      await openProfile(tester, server);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email'), 'new@example.com');
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'oldpass123');
      await tapButton(tester, 'Save and Send Code');

      // The fields above stay on screen, and the code is entered in the box.
      expect(field('Full name'), findsOneWidget);
      expect(find.text('Save Changes'), findsNothing);
      expect(find.text('Verify'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(IgnorePointer),
          matching: find.byType(Form),
        ),
        findsWidgets,
      );
      final locked = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: field('Full name'),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(locked.ignoring, isTrue);
    });

    testWidgets('the form waits for the profile so nothing jumps', (
      tester,
    ) async {
      await openProfile(tester, FakeServer());
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Fields only appear together, once the profile has loaded.
      expect(
        field('Full name').evaluate().isEmpty ==
            field('Email').evaluate().isEmpty,
        isTrue,
      );
    });

    testWidgets('a Google-linked account sees its email read-only', (
      tester,
    ) async {
      await openProfile(
        tester,
        FakeServer(hasPassword: false, isGoogleLinked: true),
      );
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();

      expect(field('Email'), findsNothing);
      expect(
        find.text("Linked to Google, so it can't be changed here."),
        findsOneWidget,
      );
    });
  });

  group('AC4 change password', () {
    testWidgets('a wrong current password shows an error and stays logged in', (
      tester,
    ) async {
      final storage = await openProfile(tester, FakeServer());

      await tapButton(tester, 'Change Password');
      await tester.enterText(field('Current password'), 'wrongpass1');
      await tester.enterText(field('New password'), 'newpass456');
      await tester.enterText(field('Retype password'), 'newpass456');
      await tapButton(tester, 'Confirm');

      expect(find.text('Your current password is incorrect.'), findsOneWidget);
      expect(storage.token, 'saved');
    });

    testWidgets('success keeps this phone logged in with the new token', (
      tester,
    ) async {
      final storage = await openProfile(tester, FakeServer());

      await tapButton(tester, 'Change Password');
      await tester.enterText(field('Current password'), 'oldpass123');
      await tester.enterText(field('New password'), 'newpass456');
      await tester.enterText(field('Retype password'), 'newpass456');
      await tapButton(tester, 'Confirm');

      expect(storage.token, 'new-token');
      expect(
        find.text(
          'Password changed. All other active sessions have been logged out.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the same password or a mismatch is caught before sending', (
      tester,
    ) async {
      final server = FakeServer();
      await openProfile(tester, server);

      await tapButton(tester, 'Change Password');
      await tester.enterText(field('Current password'), 'oldpass123');
      await tester.enterText(field('New password'), 'oldpass123');
      await tester.enterText(field('Retype password'), 'different1');
      await tapButton(tester, 'Confirm');

      expect(
        find.text('Choose a password different from your current one.'),
        findsOneWidget,
      );
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(server.last('POST', '/api/users/me/password'), isNull);
    });
  });

  group('AC5 business edit', () {
    final initial = VendorProfile.fromJson(vendorJson);

    testWidgets(
      'moving the pin warns about listings, then saves and clears the place ID',
      (tester) async {
        final server = FakeServer(role: 'vendor')
          ..summary = {
            'listingCount': 3,
            'activeListingCount': 0,
            'activeOrderCount': 0,
          };
        final page = Builder(
          builder: (context) => VendorSetupPage(
            initial: initial,
            mapBuilder: fakeMap,
            locationService: NoLocation(),
            confirmLocationChange: confirmLocationChange,
          ),
        );
        await pumpAlone(tester, server, page);

        expect(find.text('Vendor Details'), findsOneWidget);
        await tester.tap(find.text('map'));
        await tester.pumpAndSettle();
        await tapButton(tester, 'Save Changes');

        expect(
          find.text(
            'This changes the pickup location on all 3 of your listings.',
          ),
          findsOneWidget,
        );
        await tapButton(tester, 'Change Location');

        final sent = jsonDecode(server.last('PUT', '/api/vendors/me')!.body);
        expect(sent['location'], {
          'type': 'Point',
          'coordinates': [103.64, 1.56],
        });
        expect(sent.containsKey('placeId'), isFalse);
        expect(find.text('Vendor Details'), findsNothing);
      },
    );

    testWidgets('Save Changes is off until something changes', (tester) async {
      await pumpAlone(
        tester,
        FakeServer(role: 'vendor'),
        VendorSetupPage(
          initial: initial,
          mapBuilder: fakeMap,
          locationService: NoLocation(),
          confirmLocationChange: confirmLocationChange,
        ),
      );
      FilledButton save() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save Changes'),
      );

      expect(save().onPressed, isNull);
      await tester.enterText(field('Description (optional)'), 'New text');
      await tester.pump();
      expect(save().onPressed, isNotNull);
    });

    testWidgets('cancelling the warning saves nothing', (tester) async {
      final server = FakeServer(role: 'vendor')
        ..summary = {
          'listingCount': 2,
          'activeListingCount': 0,
          'activeOrderCount': 0,
        };
      await pumpAlone(
        tester,
        server,
        VendorSetupPage(
          initial: initial,
          mapBuilder: fakeMap,
          locationService: NoLocation(),
          confirmLocationChange: confirmLocationChange,
        ),
      );

      await tester.enterText(field('Pickup address'), 'Arked Meranti');
      await tapButton(tester, 'Save Changes');
      await tapButton(tester, 'Cancel');

      expect(server.last('PUT', '/api/vendors/me'), isNull);
    });

    testWidgets(
      'changing only the name skips the warning and keeps the place ID',
      (tester) async {
        final server = FakeServer(role: 'vendor');
        await pumpAlone(
          tester,
          server,
          VendorSetupPage(
            initial: initial,
            mapBuilder: fakeMap,
            locationService: NoLocation(),
            confirmLocationChange: confirmLocationChange,
          ),
        );

        await tester.enterText(field('Vendor name'), 'Warung Baru');
        await tapButton(tester, 'Save Changes');

        expect(server.last('GET', '/api/users/me/summary'), isNull);
        final sent = jsonDecode(server.last('PUT', '/api/vendors/me')!.body);
        expect(sent['stallName'], 'Warung Baru');
        expect(sent['placeId'], 'place-1');
      },
    );
  });

  group('AC6 delete account', () {
    testWidgets('active orders block deletion with an explanation', (
      tester,
    ) async {
      final server = FakeServer()
        ..summary = {
          'listingCount': 0,
          'activeListingCount': 0,
          'activeOrderCount': 2,
        };
      await openProfile(tester, server);

      await tapButton(tester, 'Delete Account');

      expect(find.text("You can't delete your account yet"), findsOneWidget);
      expect(find.textContaining('2 active orders'), findsOneWidget);
      expect(server.last('DELETE', '/api/users/me'), isNull);
    });

    testWidgets(
      'a vendor is warned about their listings, confirms with a password and is logged out',
      (tester) async {
        final server = FakeServer(role: 'vendor')
          ..summary = {
            'listingCount': 4,
            'activeListingCount': 0,
            'activeOrderCount': 0,
          };
        final storage = await openProfile(tester, server);

        await tapButton(tester, 'Delete Account');
        expect(find.text('Your 4 listings'), findsOneWidget);
        expect(find.text('Your vendor details'), findsOneWidget);
        expect(find.text('Your cart'), findsNothing);
        expect(
          find.textContaining('permanent', findRichText: true),
          findsOneWidget,
        );
        await tapButton(tester, 'Continue');

        expect(find.text('Are you sure?'), findsOneWidget);
        await tapButton(tester, 'Yes, Delete Permanently');

        await tester.enterText(field('Password'), 'wrongpass1');
        await tapButton(tester, 'Delete Permanently');
        expect(
          find.text('Your password is incorrect. 2 tries left.'),
          findsOneWidget,
        );
        expect(storage.token, 'saved');

        await tester.enterText(field('Password'), 'secret123');
        await tapButton(tester, 'Delete Permanently');

        expect(jsonDecode(server.last('DELETE', '/api/users/me')!.body), {
          'password': 'secret123',
        });
        expect(find.byType(LoginPage), findsOneWidget);
        expect(find.text(accountDeletedMessage), findsOneWidget);
        expect(storage.token, isNull);
      },
    );

    testWidgets('a Google-only account types DELETE', (tester) async {
      final server = FakeServer(hasPassword: false, isGoogleLinked: true);
      await openProfile(tester, server);

      await tapButton(tester, 'Delete Account');
      await tapButton(tester, 'Continue');
      await tapButton(tester, 'Yes, Delete Permanently');
      await tester.enterText(field('Type DELETE'), 'delete');
      await tapButton(tester, 'Delete Permanently');
      expect(find.text('Type DELETE to confirm.'), findsOneWidget);
      expect(server.last('DELETE', '/api/users/me'), isNull);

      await tester.enterText(field('Type DELETE'), 'DELETE');
      await tapButton(tester, 'Delete Permanently');
      expect(jsonDecode(server.last('DELETE', '/api/users/me')!.body), {
        'confirm': 'DELETE',
      });
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  group('AC6 delete account, more', () {
    testWidgets('keeping the account at the second question stops', (
      tester,
    ) async {
      final server = FakeServer();
      await openProfile(tester, server);

      await tapButton(tester, 'Delete Account');
      await tapButton(tester, 'Continue');
      await tapButton(tester, 'Keep My Account');

      expect(field('Password'), findsNothing);
      expect(server.last('DELETE', '/api/users/me'), isNull);
    });

    testWidgets('too many wrong tries shows the wait', (tester) async {
      final storage = await openProfile(tester, FakeServer());

      await tapButton(tester, 'Delete Account');
      await tapButton(tester, 'Continue');
      await tapButton(tester, 'Yes, Delete Permanently');
      await tester.enterText(field('Password'), 'lockedout1');
      await tapButton(tester, 'Delete Permanently');

      expect(
        find.text('Too many wrong tries. Try again in 15 minutes.'),
        findsOneWidget,
      );
      expect(storage.token, 'saved');
    });
  });

  group('lockout', () {
    String inMinutes(int minutes) =>
        DateTime.now().add(Duration(minutes: minutes)).toIso8601String();

    testWidgets('greys out Change password and says why', (tester) async {
      final server = FakeServer()..lockedUntil = inMinutes(10);
      await openProfile(tester, server);

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Change Password'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text('Locked for 10 minutes after too many wrong password tries.'),
        findsOneWidget,
      );
    });

    testWidgets('deletion says it is locked straight away', (tester) async {
      final server = FakeServer()..lockedUntil = inMinutes(3);
      await openProfile(tester, server);

      await tapButton(tester, 'Delete Account');

      expect(find.text('Too many wrong tries'), findsOneWidget);
      expect(find.textContaining('Account deletion is locked'), findsOneWidget);
      expect(server.last('GET', '/api/users/me/summary'), isNull);
    });

    testWidgets('a lock during an email change keeps the box in place', (
      tester,
    ) async {
      final server = FakeServer();
      await openProfile(tester, server);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Email'), 'new@example.com');
      await tester.pumpAndSettle();
      await tester.enterText(field('Current password'), 'lockedout1');
      final before = tester.getTopLeft(field('Current password'));
      await tapButton(tester, 'Save and Send Code');

      // Same fields, same place; the box now explains the lock.
      expect(field('Email'), findsOneWidget);
      expect(field('Current password'), findsOneWidget);
      expect(tester.getTopLeft(field('Current password')), before);
      expect(
        find.textContaining('Email changes are locked for 15 minutes'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save and Send Code'),
            )
            .onPressed,
        isNull,
      );

      // Keeping the current email lets other changes be saved.
      await tapButton(tester, 'Keep Current Email');
      expect(field('Email'), findsNothing);
      expect(find.textContaining('Email changes are locked'), findsOneWidget);
    });

    testWidgets('the email field becomes read-only', (tester) async {
      final server = FakeServer()..lockedUntil = inMinutes(1);
      await openProfile(tester, server);
      await tester.tap(find.byTooltip('Edit account details'));
      await tester.pumpAndSettle();

      expect(field('Email'), findsNothing);
      expect(
        find.textContaining('Email changes are locked for 1 minute'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the avatar shows the green ring and a spinner while loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileAvatar(name: 'Test Person', isLoading: true),
      ),
    );
    expect(find.text('TP'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            (w.decoration as BoxDecoration?)?.color == AppColors.primary,
      ),
      findsOneWidget,
    );
  });

  group('pic framing maths', () {
    const image = Size(1000, 500);

    test('starts centred, just covering the circle', () {
      final frame = PicFrame.centred(image, 200);
      final crop = frame.toCrop();
      expect(crop.x, closeTo(0.25, 0.0001));
      expect(crop.y, 0);
      expect(crop.width, closeTo(0.5, 0.0001));
      expect(crop.height, closeTo(1, 0.0001));
    });

    test('cannot move past the picture edge', () {
      final frame = PicFrame.centred(image, 200).moveBy(const Offset(999, 0));
      expect(frame.toCrop().x, 0);
      final other = frame.moveBy(const Offset(-9999, 0));
      expect(other.toCrop().x, closeTo(0.5, 0.0001));
    });

    test('zoom stays between 1x and 4x', () {
      final frame = PicFrame.centred(image, 200);
      expect(frame.zoomAround(0.2, const Offset(100, 100)).zoom, 1);
      expect(frame.zoomAround(10, const Offset(100, 100)).zoom, 4);
    });

    test('a saved crop opens where it was left', () {
      const crop = PhotoCrop(x: 0.3, y: 0.2, width: 0.25, height: 0.5);
      final again = PicFrame.fromCrop(crop, image, 300).toCrop();
      expect(again.sameAs(crop), isTrue);
    });
  });

  test('the blocked message matches the server wording', () {
    const summary = AccountSummary(
      listingCount: 3,
      activeListingCount: 1,
      activeOrderCount: 2,
    );
    expect(summary.blocksDeletion, isTrue);
    expect(
      summary.blockedMessage,
      'You have 1 active listing and 2 active orders. You can delete your '
      'account once pickup has ended for all of them.',
    );
  });

  test('a vendor profile reads its pin as [lng, lat]', () {
    final profile = VendorProfile.fromJson(vendorJson);
    expect(profile.pin, const GeoPoint(1.559, 103.6385));
    expect(profile.placeId, 'place-1');
  });
}
