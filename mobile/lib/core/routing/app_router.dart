import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/pages/complete_google_page.dart';
import '../../features/auth/presentation/pages/forgot_password_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../../features/auth/presentation/pages/reset_password_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/auth/presentation/pages/verify_email_page.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/home/presentation/pages/home_page.dart';

abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String verifyEmail = '/verify-email';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String completeGoogle = '/complete-google';
  static const String home = '/home';
}

GoRouter createAppRouter(AuthProvider auth) => GoRouter(
  initialLocation: AppRoutes.splash,
  refreshListenable: auth,
  redirect: (context, state) {
    final location = state.matchedLocation;
    if (location == AppRoutes.splash) return null;

    final signedIn = auth.status == AuthStatus.authenticated;
    if (signedIn && location != AppRoutes.home) return AppRoutes.home;
    if (!signedIn && location == AppRoutes.home) return AppRoutes.login;
    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: AppRoutes.login,
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        transitionDuration: Duration.zero,
        transitionsBuilder: (context, animation, secondary, child) => child,
        child: const LoginPage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.register,
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: AppRoutes.verifyEmail,
      builder: (context, state) =>
          VerifyEmailPage(email: state.extra as String),
    ),
    GoRoute(
      path: AppRoutes.completeGoogle,
      builder: (context, state) =>
          CompleteGooglePage(profile: state.extra as GoogleProfile),
    ),
    GoRoute(
      path: AppRoutes.forgotPassword,
      builder: (context, state) => const ForgotPasswordPage(),
    ),
    GoRoute(
      path: AppRoutes.resetPassword,
      builder: (context, state) =>
          ResetPasswordPage(email: state.extra as String),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomePage(),
    ),
  ],
);
