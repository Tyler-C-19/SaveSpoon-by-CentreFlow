import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:savespoon/features/auth/presentation/pages/complete_google_page.dart';
import 'package:savespoon/features/auth/presentation/pages/login_page.dart';
import 'package:savespoon/features/auth/presentation/pages/reset_password_page.dart';
import 'package:savespoon/features/auth/presentation/pages/verify_email_page.dart';
import 'package:savespoon/features/home/presentation/pages/home_page.dart';

import 'helpers.dart';

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> tapButton(WidgetTester tester, String label) async {
  await tester.tap(
    find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> leaveTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('AC1, AC3: register, enter the code, reach home', (tester) async {
    final storage = FakeTokenStorage();
    final calls = <String, Map<String, dynamic>>{};
    await startApp(
      tester,
      storage: storage,
      onRequest: (request) async {
        calls[request.url.path] =
            jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/api/auth/register') {
          return jsonResponse({
            'email': 'person@example.com',
            'emailSent': true,
          }, 201);
        }
        return jsonResponse({'token': 'tok', 'user': userJson});
      },
    );

    await tester.tap(find.text('Email').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vendor'));
    await tester.pump();
    await tester.enterText(field('Full name'), 'Test Person');
    await tester.enterText(field('Email'), 'person@example.com');
    await tester.enterText(field('Phone number'), '012-3456789');
    await tester.enterText(field('Password'), 'Secret123');
    await tester.enterText(field('Confirm password'), 'Secret123');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tapButton(tester, 'Create Account');

    expect(calls['/api/auth/register']!['role'], 'vendor');
    expect(calls['/api/auth/register']!['acceptedTerms'], true);
    expect(find.byType(VerifyEmailPage), findsOneWidget);
    expect(find.textContaining('Resend code in'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tapButton(tester, 'Verify');

    expect(calls['/api/auth/verify-email'], {
      'email': 'person@example.com',
      'code': '123456',
    });
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Welcome back, Test Person'), findsOneWidget);
    expect(storage.token, 'tok');
  });

  testWidgets('AC2: invalid details and no Terms tick send nothing', (
    tester,
  ) async {
    var requests = 0;
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (_) async {
        requests++;
        return jsonResponse({});
      },
    );
    await tester.tap(find.text('Email').last);
    await tester.pumpAndSettle();

    await tapButton(tester, 'Create Account');
    expect(find.text('Enter your full name.'), findsOneWidget);

    await tester.enterText(field('Full name'), 'Test Person');
    await tester.enterText(field('Email'), 'person@example.com');
    await tester.enterText(field('Phone number'), '012-3456789');
    await tester.enterText(field('Password'), 'Secret123');
    await tester.enterText(field('Confirm password'), 'Different123');
    await tapButton(tester, 'Create Account');
    expect(find.text('Passwords do not match.'), findsOneWidget);

    await tester.enterText(field('Confirm password'), 'Secret123');
    await tapButton(tester, 'Create Account');
    expect(
      find.text('Accept the Terms and Privacy Policy to continue.'),
      findsOneWidget,
    );
    expect(requests, 0);
  });

  testWidgets('AC2: an email already in use shows the server message', (
    tester,
  ) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (_) async => jsonResponse({
        'error': 'An account with this email already exists.',
      }, 409),
    );
    await tester.tap(find.text('Email').last);
    await tester.pumpAndSettle();
    await tester.enterText(field('Full name'), 'Test Person');
    await tester.enterText(field('Email'), 'person@example.com');
    await tester.enterText(field('Phone number'), '012-3456789');
    await tester.enterText(field('Password'), 'Secret123');
    await tester.enterText(field('Confirm password'), 'Secret123');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tapButton(tester, 'Create Account');

    expect(
      find.text('An account with this email already exists.'),
      findsOneWidget,
    );
    expect(find.byType(VerifyEmailPage), findsNothing);
  });

  testWidgets('AC3: a short or wrong code shows an error', (tester) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (request) async {
        if (request.url.path == '/api/auth/login') {
          return jsonResponse({
            'error': 'Verify your email to continue.',
            'code': 'EMAIL_NOT_VERIFIED',
            'email': 'person@example.com',
          }, 403);
        }
        return jsonResponse({
          'error': 'That code is wrong or has expired.',
        }, 400);
      },
    );
    await tester.enterText(field('Email'), 'person@example.com');
    await tester.enterText(field('Password'), 'Secret123');
    await tapButton(tester, 'Login');
    expect(find.byType(VerifyEmailPage), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12');
    await tapButton(tester, 'Verify');
    expect(find.text('Enter the 6-digit code.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tapButton(tester, 'Verify');
    expect(find.text('That code is wrong or has expired.'), findsOneWidget);
    await leaveTimers(tester);
  });

  testWidgets('AC3: resend unlocks after 60 seconds', (tester) async {
    var resends = 0;
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (request) async {
        if (request.url.path == '/api/auth/resend-verification') {
          resends++;
          return jsonResponse({'message': 'ok'});
        }
        return jsonResponse({
          'error': 'Verify your email to continue.',
          'code': 'EMAIL_NOT_VERIFIED',
        }, 403);
      },
    );
    await tester.enterText(field('Email'), 'person@example.com');
    await tester.enterText(field('Password'), 'Secret123');
    await tapButton(tester, 'Login');

    await tester.tap(
      find.textContaining('Resend code in'),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(resends, 0);

    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    expect(resends, 1);
    expect(find.textContaining('Resend code in'), findsOneWidget);
    await leaveTimers(tester);
  });

  testWidgets('AC4: wrong login shows the error, correct login reaches home', (
    tester,
  ) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (request) async {
        final body = jsonDecode(request.body);
        return body['password'] == 'Secret123'
            ? jsonResponse({'token': 'tok', 'user': userJson})
            : jsonResponse({'error': 'Incorrect email or password.'}, 401);
      },
    );

    await tapButton(tester, 'Login');
    expect(find.text('Enter your password.'), findsOneWidget);

    await tester.enterText(field('Email'), 'person@example.com');
    await tester.enterText(field('Password'), 'Wrong1234');
    await tapButton(tester, 'Login');
    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(find.byType(LoginPage), findsOneWidget);

    await tester.enterText(field('Password'), 'Secret123');
    await tapButton(tester, 'Login');
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('AC4: a server that cannot be reached shows a clear error', (
    tester,
  ) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (_) async => throw http.ClientException('down'),
    );
    await tester.enterText(field('Email'), 'person@example.com');
    await tester.enterText(field('Password'), 'Secret123');
    await tapButton(tester, 'Login');
    expect(find.text('Cannot reach the server.'), findsOneWidget);
  });

  testWidgets('AC5: forgot password, enter the code, set a new password', (
    tester,
  ) async {
    Map<String, dynamic>? reset;
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      onRequest: (request) async {
        if (request.url.path == '/api/auth/reset-password') {
          reset = jsonDecode(request.body) as Map<String, dynamic>;
        }
        return jsonResponse({'message': 'ok'});
      },
    );

    await tapButton(tester, 'Forgot password?');
    await tester.enterText(field('Email'), 'person@example.com');
    await tapButton(tester, 'Send code');
    expect(find.byType(ResetPasswordPage), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '654321');
    await tester.enterText(field('New password'), 'NewSecret456');
    await tester.enterText(field('Retype password'), 'NewSecret456');
    await tapButton(tester, 'Confirm');

    expect(reset, {
      'email': 'person@example.com',
      'code': '654321',
      'newPassword': 'NewSecret456',
    });
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('AC6: a returning Google user goes straight home', (
    tester,
  ) async {
    final storage = FakeTokenStorage();
    Map<String, dynamic>? sent;
    await startApp(
      tester,
      storage: storage,
      googleAuth: FakeGoogleAuth(idToken: 'google-token'),
      onRequest: (request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({'token': 'tok', 'user': userJson});
      },
    );
    await tapButton(tester, 'Continue with Google');
    expect(sent, {'idToken': 'google-token'});
    expect(find.byType(HomePage), findsOneWidget);
    expect(storage.token, 'tok');
  });

  testWidgets('AC6: a first-time Google user finishes signing up', (
    tester,
  ) async {
    Map<String, dynamic>? completed;
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      googleAuth: FakeGoogleAuth(idToken: 'google-token'),
      onRequest: (request) async {
        if (request.url.path == '/api/auth/google') {
          return jsonResponse({
            'needsProfile': true,
            'email': 'person@example.com',
            'name': 'Test Person',
          });
        }
        completed = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({'token': 'tok', 'user': userJson}, 201);
      },
    );

    await tapButton(tester, 'Continue with Google');
    expect(find.byType(CompleteGooglePage), findsOneWidget);
    expect(find.textContaining('person@example.com'), findsOneWidget);

    await tapButton(tester, 'Finish signing up');
    expect(find.text('Enter a valid phone number.'), findsOneWidget);

    await tester.enterText(field('Phone number'), '012-3456789');
    await tapButton(tester, 'Finish signing up');
    expect(
      find.text('Accept the Terms and Privacy Policy to continue.'),
      findsOneWidget,
    );
    expect(completed, isNull);

    await tester.tap(find.text('Vendor'));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tapButton(tester, 'Finish signing up');

    expect(completed, {
      'idToken': 'google-token',
      'role': 'vendor',
      'phone': '012-3456789',
      'acceptedTerms': true,
    });
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('AC6: cancelling Google stays on login with no error', (
    tester,
  ) async {
    var requests = 0;
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      googleAuth: FakeGoogleAuth(),
      onRequest: (_) async {
        requests++;
        return jsonResponse({});
      },
    );
    await tapButton(tester, 'Continue with Google');
    expect(requests, 0);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('AC6: a rejected Google token shows an error', (tester) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(),
      googleAuth: FakeGoogleAuth(idToken: 'bad'),
      onRequest: (_) async =>
          jsonResponse({'error': 'Google sign-in failed. Try again.'}, 401),
    );
    await tapButton(tester, 'Continue with Google');
    expect(find.text('Google sign-in failed. Try again.'), findsOneWidget);
  });

  testWidgets('AC7: logging out also signs out of Google', (tester) async {
    final google = FakeGoogleAuth();
    await startApp(
      tester,
      storage: FakeTokenStorage(token: 'saved'),
      googleAuth: google,
      onRequest: (_) async => jsonResponse({'user': userJson}),
    );
    await tapButton(tester, 'Log out');
    expect(google.signOuts, 1);
  });

  testWidgets('AC7: reopening with a valid token goes straight home', (
    tester,
  ) async {
    String? authHeader;
    await startApp(
      tester,
      storage: FakeTokenStorage(token: 'saved'),
      onRequest: (request) async {
        authHeader = request.headers['Authorization'];
        return jsonResponse({'user': userJson});
      },
    );
    expect(authHeader, 'Bearer saved');
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('AC7: an expired token clears the session and returns to login', (
    tester,
  ) async {
    final storage = FakeTokenStorage(token: 'expired');
    await startApp(
      tester,
      storage: storage,
      onRequest: (_) async => jsonResponse({'error': 'Expired'}, 401),
    );
    expect(find.byType(LoginPage), findsOneWidget);
    expect(storage.token, isNull);
  });

  testWidgets('AC7: being offline keeps the saved session', (tester) async {
    await startApp(
      tester,
      storage: FakeTokenStorage(token: 'saved', userJson: jsonEncode(userJson)),
      onRequest: (_) async => throw http.ClientException('offline'),
    );
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Welcome back, Test Person'), findsOneWidget);
  });

  testWidgets('AC7: logging out clears the session', (tester) async {
    final storage = FakeTokenStorage(token: 'saved');
    await startApp(
      tester,
      storage: storage,
      onRequest: (_) async => jsonResponse({'user': userJson}),
    );
    await tapButton(tester, 'Log out');
    expect(find.byType(LoginPage), findsOneWidget);
    expect(storage.token, isNull);
  });
}
