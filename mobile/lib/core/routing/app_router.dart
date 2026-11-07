import 'package:flutter/widgets.dart';
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
import '../../features/home/presentation/pages/placeholder_page.dart';
import '../../features/home/presentation/widgets/role_shell.dart';
import '../../features/seller_profile/presentation/pages/vendor_setup_page.dart';
import '../theme/app_theme.dart';

abstract final class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String verifyEmail = '/verify-email';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String completeGoogle = '/complete-google';
  static const String customerHome = '/customer/home';
  static const String customerSearch = '/customer/search';
  static const String customerOrders = '/customer/orders';
  static const String customerProfile = '/customer/profile';
  static const String vendorSetup = '/vendor/setup';
  static const String vendorHome = '/vendor/home';
  static const String vendorListings = '/vendor/listings';
  static const String vendorOrders = '/vendor/orders';
  static const String vendorProfile = '/vendor/profile';

  static String homeFor(String? role) =>
      role == 'vendor' ? vendorHome : customerHome;
}

String? resolveRedirect({
  required String location,
  required bool signedIn,
  String? role,
  bool needsVendorSetup = false,
}) {
  if (location == AppRoutes.splash) return null;

  if (!signedIn) {
    final inApp =
        location.startsWith('/customer/') || location.startsWith('/vendor/');
    return inApp ? AppRoutes.login : null;
  }
  if (needsVendorSetup) {
    return location == AppRoutes.vendorSetup ? null : AppRoutes.vendorSetup;
  }
  if (location == AppRoutes.vendorSetup) return AppRoutes.homeFor(role);
  return location.startsWith('/$role/') ? null : AppRoutes.homeFor(role);
}

StatefulShellBranch _tab(String path, Widget page) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => page)],
);

Page<void> _fadeInPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondary, child) => ColoredBox(
        color: AppColors.page,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: child,
    );

GoRouter createAppRouter(AuthProvider auth) => GoRouter(
  initialLocation: AppRoutes.splash,
  refreshListenable: auth,
  redirect: (context, state) => resolveRedirect(
    location: state.matchedLocation,
    signedIn: auth.status == AuthStatus.authenticated,
    role: auth.user?.role,
    needsVendorSetup: auth.user?.needsVendorSetup ?? false,
  ),
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashPage(),
    ),
    GoRoute(
      path: AppRoutes.login,
      pageBuilder: (context, state) => state.extra == AppRoutes.splash
          ? CustomTransitionPage(
              key: state.pageKey,
              transitionDuration: Duration.zero,
              transitionsBuilder: (context, animation, secondary, child) =>
                  child,
              child: const LoginPage(sheetRises: false),
            )
          : _fadeInPage(state, const LoginPage()),
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
      path: AppRoutes.vendorSetup,
      pageBuilder: (context, state) =>
          _fadeInPage(state, const VendorSetupPage()),
    ),
    StatefulShellRoute.indexedStack(
      pageBuilder: (context, state, shell) => _fadeInPage(
        state,
        RoleShell(shell: shell, tabs: RoleShell.customerTabs),
      ),
      branches: [
        _tab(AppRoutes.customerHome, const HomePage()),
        _tab(AppRoutes.customerSearch, const PlaceholderPage(title: 'Search')),
        _tab(AppRoutes.customerOrders, const PlaceholderPage(title: 'Orders')),
        _tab(AppRoutes.customerProfile, const ProfilePlaceholderPage()),
      ],
    ),
    StatefulShellRoute.indexedStack(
      pageBuilder: (context, state, shell) => _fadeInPage(
        state,
        RoleShell(shell: shell, tabs: RoleShell.vendorTabs),
      ),
      branches: [
        _tab(AppRoutes.vendorHome, const HomePage()),
        _tab(AppRoutes.vendorListings, const PlaceholderPage(title: 'Listings')),
        _tab(AppRoutes.vendorOrders, const PlaceholderPage(title: 'Orders')),
        _tab(AppRoutes.vendorProfile, const ProfilePlaceholderPage()),
      ],
    ),
  ],
);
