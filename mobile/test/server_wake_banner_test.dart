import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/core/theme/app_theme.dart';
import 'package:savespoon/core/widgets/error_text.dart';
import 'package:savespoon/core/widgets/load_error.dart';
import 'package:savespoon/core/widgets/server_wake_banner.dart';
import 'package:savespoon/features/auth/presentation/pages/login_page.dart';
import 'package:savespoon/main.dart';

import 'helpers.dart';

Widget bannerOver(ValueNotifier<ServerWait> wait) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, child) =>
      ServerWakeBanner(serverWait: wait, child: child!),
  home: const Scaffold(body: Center(child: Text('Page content'))),
);

void main() {
  testWidgets('shows the matching message over the page, then clears', (
    tester,
  ) async {
    final wait = ValueNotifier(ServerWait.none);
    addTearDown(wait.dispose);
    await tester.pumpWidget(bannerOver(wait));

    expect(find.byKey(ServerWakeBanner.bannerKey), findsNothing);
    expect(find.text('Page content'), findsOneWidget);

    wait.value = ServerWait.waking;
    await tester.pumpAndSettle();
    expect(find.text(ServerWakeBanner.wakingMessage), findsOneWidget);
    expect(find.text('Page content'), findsOneWidget);

    wait.value = ServerWait.slow;
    await tester.pumpAndSettle();
    expect(find.text(ServerWakeBanner.slowMessage), findsOneWidget);
    expect(find.text(ServerWakeBanner.wakingMessage), findsNothing);

    wait.value = ServerWait.none;
    await tester.pumpAndSettle();
    expect(find.byKey(ServerWakeBanner.bannerKey), findsNothing);
  });

  testWidgets('sits at the top, below the status bar', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 48);
    addTearDown(tester.view.reset);
    final wait = ValueNotifier(ServerWait.waking);
    addTearDown(wait.dispose);
    await tester.pumpWidget(bannerOver(wait));
    await tester.pumpAndSettle();

    final top = tester.getTopLeft(find.byKey(ServerWakeBanner.bannerKey)).dy;
    expect(top, closeTo(48 / tester.view.devicePixelRatio, 1));
  });

  testWidgets('server-down errors show a plug icon; others do not', (
    tester,
  ) async {
    Future<void> show(String message) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ErrorText(message)),
      ),
    );

    for (final message in ServerMessages.all) {
      await show(message);
      expect(find.byIcon(Icons.power_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text(message), findsOneWidget);
    }

    await show('Incorrect email or password.');
    expect(find.byIcon(Icons.power_off_outlined), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('a failed load shows a plug for server-down errors only', (
    tester,
  ) async {
    var retries = 0;
    Future<void> show(String message, {String? title}) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: LoadError(
            title: title,
            message: message,
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    for (final message in ServerMessages.all) {
      await show(message, title: "Couldn't load your latest details");
      expect(find.byIcon(Icons.power_off_outlined), findsOneWidget);
      expect(find.text("Couldn't load your latest details"), findsOneWidget);
      expect(find.text(message), findsOneWidget);
    }

    await show('Could not load.');
    expect(find.byIcon(Icons.power_off_outlined), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    expect(retries, 1);
  });

  testWidgets('a quick server shows no banner on opening the app', (
    tester,
  ) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (request) async => jsonResponse({}),
    );

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byKey(ServerWakeBanner.bannerKey), findsNothing);
  });

  testWidgets(
    'opening the app wakes the server and shows the banner while it starts',
    (tester) async {
      final paths = <String>[];
      await tester.pumpWidget(
        SaveSpoonApp(
          storage: FakeTokenStorage(),
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            await Future<void>.delayed(const Duration(seconds: 8));
            return jsonResponse({'status': 'ok'});
          }),
          googleAuth: FakeGoogleAuth(),
        ),
      );
      await tester.pump();
      expect(paths, ['/api/health']);

      await tester.pump(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(ServerWakeBanner.wakingMessage), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(ServerWakeBanner.bannerKey), findsNothing);
      expect(find.byType(LoginPage), findsOneWidget);
    },
  );
}
