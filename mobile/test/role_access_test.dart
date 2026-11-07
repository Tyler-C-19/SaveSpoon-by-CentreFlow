import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:savespoon/core/routing/app_router.dart';
import 'package:savespoon/features/auth/presentation/pages/login_page.dart';
import 'package:savespoon/features/auth/presentation/pages/splash_page.dart';
import 'package:savespoon/features/home/presentation/pages/home_page.dart';
import 'package:savespoon/main.dart';

import 'helpers.dart';

Map<String, dynamic> userWithRole(String role) => {...userJson, 'role': role};

Future<void> startAs(
  WidgetTester tester,
  String role, {
  FakeTokenStorage? storage,
}) => startApp(
  tester,
  storage: storage ?? FakeTokenStorage(token: 'saved'),
  onRequest: (_) async => jsonResponse({'user': userWithRole(role)}),
);

void main() {
  group('resolveRedirect', () {
    String? redirect(String location, {bool signedIn = true, String? role}) =>
        resolveRedirect(location: location, signedIn: signedIn, role: role);

    test('leaves the splash alone', () {
      expect(redirect(AppRoutes.splash, role: 'vendor'), isNull);
    });

    test('keeps each role inside its own routes', () {
      expect(redirect(AppRoutes.customerOrders, role: 'customer'), isNull);
      expect(redirect(AppRoutes.vendorListings, role: 'vendor'), isNull);
    });

    test('sends each role away from the other role', () {
      expect(
        redirect(AppRoutes.vendorListings, role: 'customer'),
        AppRoutes.customerHome,
      );
      expect(
        redirect(AppRoutes.customerSearch, role: 'vendor'),
        AppRoutes.vendorHome,
      );
    });

    test('sends signed-in users away from login', () {
      expect(redirect(AppRoutes.login, role: 'vendor'), AppRoutes.vendorHome);
    });

    test('sends signed-out users to login', () {
      expect(
        redirect(AppRoutes.vendorHome, signedIn: false),
        AppRoutes.login,
      );
      expect(
        redirect(AppRoutes.customerHome, signedIn: false),
        AppRoutes.login,
      );
      expect(redirect(AppRoutes.register, signedIn: false), isNull);
    });
  });

  group('reopening the app', () {
    Future<void> open(
      WidgetTester tester,
      FakeTokenStorage storage,
      Future<http.Response> Function() me,
    ) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        SaveSpoonApp(
          storage: storage,
          httpClient: MockClient((_) => me()),
          googleAuth: FakeGoogleAuth(),
        ),
      );
      await tester.pump();
    }

    Future<void> playSplash(WidgetTester tester) async {
      for (var i = 0; i < 80; i++) {
        await tester.pump(SplashPage.displayTime * 0.0125);
        if (find.byKey(SplashPage.sheetKey).evaluate().isEmpty) continue;
        final top = tester.getTopLeft(find.byKey(SplashPage.sheetKey)).dy;
        expect(top, greaterThanOrEqualTo(3000 - 1), reason: 'login panel rose');
      }
    }

    testWidgets('with a cached user, goes home without the login panel', (
      tester,
    ) async {
      final slow = Completer<http.Response>();
      await open(
        tester,
        FakeTokenStorage(token: 'saved', userJson: jsonEncode(userJson)),
        () => slow.future,
      );

      expect(find.byKey(SplashPage.sheetKey), findsNothing);
      await tester.pump(SplashPage.displayTime * 0.5);
      expect(find.byKey(SplashPage.logoKey), findsOneWidget);
      await tester.pump(SplashPage.displayTime * 0.1);
      await tester.pumpAndSettle();

      expect(find.byType(HomePage), findsOneWidget);
      expect(find.byType(SplashPage), findsNothing);
      slow.complete(jsonResponse({'user': userJson}));
      await tester.pumpAndSettle();
    });

    testWidgets('while the server is slow, holds on the logo', (tester) async {
      final slow = Completer<http.Response>();
      await open(tester, FakeTokenStorage(token: 'saved'), () => slow.future);

      await playSplash(tester);
      expect(find.byKey(SplashPage.logoKey), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);

      slow.complete(jsonResponse({'user': userJson}));
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('an expired token still rises into login', (tester) async {
      final slow = Completer<http.Response>();
      final storage = FakeTokenStorage(token: 'expired');
      await open(tester, storage, () => slow.future);

      await playSplash(tester);
      slow.complete(jsonResponse({'error': 'Expired'}, 401));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(SplashPage.displayTime * 0.2);
      expect(
        tester.getTopLeft(find.byKey(SplashPage.sheetKey)).dy,
        lessThan(3000),
      );

      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(storage.token, isNull);
    });

    testWidgets('a saved session reaches home with animations off', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(
        tester,
        FakeTokenStorage(token: 'saved'),
        () async => jsonResponse({'user': userJson}),
      );

      expect(find.text('Welcome back'), findsNothing);
      await tester.pump(SplashPage.displayTime);
      await tester.pumpAndSettle();
      expect(find.byType(HomePage), findsOneWidget);
    });

    testWidgets('logging out during the server check stays logged out', (
      tester,
    ) async {
      final slow = Completer<http.Response>();
      final storage = FakeTokenStorage(
        token: 'saved',
        userJson: jsonEncode(userJson),
      );
      await open(tester, storage, () => slow.future);
      await tester.pump(SplashPage.displayTime);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);

      slow.complete(jsonResponse({'user': userJson}));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
    });
  });

  testWidgets('logging out shows the login form rising', (tester) async {
    await startAs(tester, 'customer');
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));

    for (var i = 0; i < 10 && find.byType(LoginPage).evaluate().isEmpty; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    final rising = tester.getTopLeft(find.byType(LoginSheet)).dy;

    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(find.byType(LoginSheet)).dy;
    expect(rising, greaterThan(settled));
  });

  testWidgets('logged out, the splash plays and the form floats up', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      SaveSpoonApp(
        storage: FakeTokenStorage(),
        httpClient: MockClient((_) async => jsonResponse({})),
        googleAuth: FakeGoogleAuth(),
      ),
    );
    await tester.pump();

    double sheetTop() => tester.getTopLeft(find.byKey(SplashPage.sheetKey)).dy;

    final tops = <double>[];
    for (var i = 0; i < 19; i++) {
      await tester.pump(SplashPage.displayTime * 0.05);
      expect(find.byKey(SplashPage.logoKey), findsOneWidget);
      tops.add(sheetTop());
    }

    expect(tops[9], 3000, reason: 'still below the screen at the halfway mark');
    expect(tops[14], lessThan(3000), reason: 'rising by three quarters');
    expect(tops[14], greaterThan(tops[18]), reason: 'keeps rising');

    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('the login form is already in place after the splash', (
    tester,
  ) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (_) async => jsonResponse({}),
    );
    final page = tester.widget<LoginPage>(find.byType(LoginPage));
    expect(page.sheetRises, isFalse);
  });

  testWidgets('a customer sees the customer tabs', (tester) async {
    await startAs(tester, 'customer');

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Listings'), findsNothing);
    expect(find.text('Cart'), findsNothing);
  });

  testWidgets('a vendor sees the vendor tabs', (tester) async {
    await startAs(tester, 'vendor');

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Listings'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
  });

  testWidgets('the bottom bar floats clear of the screen edges', (
    tester,
  ) async {
    await startAs(tester, 'customer');

    final bar = tester.getRect(find.byType(NavigationBar));
    final screen = tester.getRect(find.byType(Scaffold).first);

    expect(bar.left, greaterThan(screen.left));
    expect(bar.right, lessThan(screen.right));
    expect(bar.bottom, lessThan(screen.bottom));
  });

  testWidgets('tabs open their placeholder pages', (tester) async {
    await startAs(tester, 'vendor');

    await tester.tap(find.text('Listings'));
    await tester.pumpAndSettle();

    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets('a vendor opening a customer route returns to vendor home', (
    tester,
  ) async {
    await startAs(tester, 'vendor');

    GoRouter.of(
      tester.element(find.byType(HomePage)),
    ).go(AppRoutes.customerOrders);
    await tester.pumpAndSettle();

    expect(find.text('Listings'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
  });

  testWidgets('a saved admin session logs out', (tester) async {
    final storage = FakeTokenStorage(token: 'saved');
    await startAs(tester, 'admin', storage: storage);

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(storage.token, isNull);
  });

  testWidgets('a cached admin session logs out when offline', (tester) async {
    final storage = FakeTokenStorage(
      token: 'saved',
      userJson: jsonEncode(userWithRole('admin')),
    );
    await startApp(
      tester,
      storage: storage,
      onRequest: (_) async => throw http.ClientException('offline'),
    );

    expect(find.byType(LoginPage), findsOneWidget);
    expect(storage.token, isNull);
  });

  testWidgets('admin login shows the message from the server', (tester) async {
    const message =
        "Admin accounts can't use the mobile app. Use the admin dashboard.";
    final storage = FakeTokenStorage();
    await startApp(
      tester,
      storage: storage,
      onRequest: (_) async => jsonResponse({
        'error': message,
        'code': 'ADMIN_USE_DASHBOARD',
      }, 403),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'boss@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Secret123',
    );
    await tester.tap(
      find.ancestor(
        of: find.text('Login'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(storage.token, isNull);
  });
}
