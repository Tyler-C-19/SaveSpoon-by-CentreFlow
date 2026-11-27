import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/server_wake_banner.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/google_auth_service.dart';
import 'features/auth/data/token_storage.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/cart/data/cart_repository.dart';
import 'features/cart/presentation/providers/cart_provider.dart';
import 'features/listings/data/favourites_repository.dart';
import 'features/listings/data/listing_repository.dart';
import 'features/listings/presentation/providers/favourites_provider.dart';
import 'features/listings/presentation/providers/listing_changes.dart';
import 'features/notifications/data/firebase_push_platform.dart';
import 'features/notifications/data/notification_repository.dart';
import 'features/notifications/data/push_platform.dart';
import 'features/notifications/presentation/providers/notifications_controller.dart';
import 'features/orders/data/order_repository.dart';
import 'features/profile/data/profile_repository.dart';
import 'features/seller_profile/data/vendor_repository.dart';
import 'features/map/data/position_source.dart';
import 'features/map/presentation/providers/user_location_provider.dart';

void main() {
  runApp(SaveSpoonApp(push: FirebasePushPlatform()));
}

class SaveSpoonApp extends StatefulWidget {
  const SaveSpoonApp({
    super.key,
    this.storage,
    this.httpClient,
    this.push,
    this.googleAuth,
    this.positionSource,
  });

  final TokenStorage? storage;
  final http.Client? httpClient;
  final GoogleAuthService? googleAuth;
  final PositionSource? positionSource;

  // Firebase on phones; nothing in tests.
  final PushPlatform? push;

  @override
  State<SaveSpoonApp> createState() => _SaveSpoonAppState();
}

class _SaveSpoonAppState extends State<SaveSpoonApp> {
  final AuthProvider _auth = AuthProvider();
  late final ApiClient _api;
  final ListingChanges _listingChanges = ListingChanges();
  late final CartProvider _cart;
  late final NotificationRepository _notificationRepository;
  late final NotificationsController _notifications;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final storage = widget.storage ?? SecureTokenStorage();
    _api = ApiClient(
      client: widget.httpClient,
      tokenReader: storage.readToken,
      onUnauthorized: _auth.handleSessionExpired,
    );
    _api.wakeUp();
    _cart = CartProvider(CartRepository(_api));
    _auth.addListener(_resetCartAfterLogout);
    _notificationRepository = NotificationRepository(_api);
    _notifications = NotificationsController(
      platform: widget.push ?? const NoPush(),
      repository: _notificationRepository,
      orders: OrderRepository(_api),
    );
    _auth.beforeLogout = _notifications.beforeSignOut;
    _auth.addListener(_followSignIn);
    _auth.attach(
      AuthRepository(api: _api, storage: storage),
      widget.googleAuth ?? PluginGoogleAuthService(),
    );
    _auth.restoreSession();
    _router = createAppRouter(_auth);
  }

  void _resetCartAfterLogout() {
    final signedOut = _auth.status != AuthStatus.authenticated;
    if (signedOut && _cart.cart != null) _cart.reset();
  }

  // Registers this phone for the signed-in user, and forgets it on sign-out.
  // Tests pass no push platform, so the app makes no notification calls.
  void _followSignIn() {
    if (widget.push == null) return;
    final user = _auth.user;
    if (_auth.status == AuthStatus.authenticated && user != null) {
      if (_notifications.role != user.role) _notifications.signedIn(user.role);
    } else if (_notifications.role != null) {
      _notifications.beforeSignOut();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_resetCartAfterLogout);
    _auth.removeListener(_followSignIn);
    _notifications.dispose();
    _cart.dispose();
    _listingChanges.dispose();
    _router.dispose();
    _auth.dispose();
    _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        Provider<VendorRepository>(create: (_) => VendorRepository(_api)),
        Provider<ListingRepository>(create: (_) => ListingRepository(_api)),
        Provider<OrderRepository>(create: (_) => OrderRepository(_api)),
        Provider<ProfileRepository>(create: (_) => ProfileRepository(_api)),
        Provider<NotificationRepository>.value(value: _notificationRepository),
        ChangeNotifierProvider<NotificationsController>.value(
          value: _notifications,
        ),
        ChangeNotifierProvider<CartProvider>.value(value: _cart),
        ChangeNotifierProvider<ListingChanges>.value(value: _listingChanges),
        ChangeNotifierProvider<FavouritesProvider>(
          create: (_) => FavouritesProvider(FavouritesRepository(_api)),
        ),
        ChangeNotifierProvider<UserLocationProvider>(
          create: (_) => UserLocationProvider(
            widget.positionSource ?? DevicePositionSource(),
          )..start(),
        ),
      ],
      child: MaterialApp.router(
        title: 'SaveSpoon',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
        builder: (context, child) => ServerWakeBanner(
          serverWait: _api.serverWait,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
