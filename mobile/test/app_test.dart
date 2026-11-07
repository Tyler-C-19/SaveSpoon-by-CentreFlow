import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/features/auth/presentation/pages/login_page.dart';
import 'package:savespoon/features/auth/presentation/pages/splash_page.dart';
import 'package:savespoon/features/auth/presentation/widgets/brand_header.dart';
import 'package:savespoon/main.dart';

import 'helpers.dart';

Widget app() => SaveSpoonApp(
  storage: FakeTokenStorage(),
  httpClient: MockClient((_) async => throw UnimplementedError()),
  googleAuth: FakeGoogleAuth(),
);

void main() {
  testWidgets('shows the animated splash, then moves to login', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    expect(find.byKey(SplashPage.logoKey), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    await tester.pump(SplashPage.displayTime);
    await tester.pumpAndSettle();

    expect(find.byKey(SplashPage.logoKey), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('the white panel is already in place as the splash ends', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump(SplashPage.displayTime * 0.99);

    final top = tester.getTopLeft(find.byKey(SplashPage.sheetKey)).dy;
    expect(top, closeTo(BrandHeader.height, 5));
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(SplashPage), findsOneWidget);

    await tester.pump(SplashPage.displayTime);
    await tester.pumpAndSettle();
  });

  testWidgets('the app uses the green Material 3 theme', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(SplashPage)));
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, AppColors.primary);

    await tester.pump(SplashPage.displayTime);
    await tester.pumpAndSettle();
  });

  testWidgets('the splash still moves on with animations turned off', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byKey(SplashPage.logoKey), findsOneWidget);

    await tester.pump(SplashPage.displayTime);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
