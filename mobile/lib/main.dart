import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'core/network/api_client.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/google_auth_service.dart';
import 'features/auth/data/token_storage.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/cart/data/cart_repository.dart';
import 'features/cart/presentation/providers/cart_provider.dart';
import 'features/listings/data/listing_repository.dart';
import 'features/listings/presentation/providers/listing_changes.dart';
import 'features/orders/data/order_repository.dart';
import 'features/seller_profile/data/vendor_repository.dart';

void main() {
  runApp(const SaveSpoonApp());
}

class SaveSpoonApp extends StatefulWidget {
  const SaveSpoonApp({
    super.key,
    this.storage,
    this.httpClient,
    this.googleAuth,
  });

  final TokenStorage? storage;
  final http.Client? httpClient;
  final GoogleAuthService? googleAuth;

  @override
  State<SaveSpoonApp> createState() => _SaveSpoonAppState();
}

class _SaveSpoonAppState extends State<SaveSpoonApp> {
  final AuthProvider _auth = AuthProvider();
  late final ApiClient _api;
  final ListingChanges _listingChanges = ListingChanges();
  late final CartProvider _cart;
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
    _cart = CartProvider(CartRepository(_api));
    _auth.addListener(_resetCartAfterLogout);
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

  @override
  void dispose() {
    _auth.removeListener(_resetCartAfterLogout);
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
        ChangeNotifierProvider<CartProvider>.value(value: _cart),
        ChangeNotifierProvider<ListingChanges>.value(value: _listingChanges),
      ],
      child: MaterialApp.router(
        title: 'SaveSpoon',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: _router,
      ),
    );
  }
}
