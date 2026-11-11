import '../../../core/network/api_client.dart';
import '../../orders/domain/order.dart';
import '../domain/cart.dart';

class CartUpdate {
  const CartUpdate({required this.cart, required this.message});

  final Cart cart;
  final String message;
}

class CartRepository {
  CartRepository(this.api);

  final ApiClient api;

  Cart _parseCart(dynamic data) =>
      Cart.fromJson(data['cart'] as Map<String, dynamic>);

  Future<Cart> fetch() async => _parseCart(await api.get('/api/cart'));

  Future<CartUpdate> add(String listingId, int quantity) async {
    final data = await api.post(
      '/api/cart/items',
      body: {'listingId': listingId, 'quantity': quantity},
    );
    return CartUpdate(
      cart: _parseCart(data),
      message: data['message'] as String? ?? 'Added to cart.',
    );
  }

  Future<Cart> setQuantity(String listingId, int quantity) async => _parseCart(
    await api.patch('/api/cart/items/$listingId', body: {'quantity': quantity}),
  );

  Future<Cart> remove(String listingId) async =>
      _parseCart(await api.delete('/api/cart/items/$listingId'));

  Future<Cart> removeUnavailable() async =>
      _parseCart(await api.delete('/api/cart/unavailable'));

  Future<Cart> clear() async => _parseCart(await api.delete('/api/cart'));

  Future<List<Order>> checkout({
    required String requestId,
    required double expectedTotal,
  }) async {
    final data = await api.post(
      '/api/cart/checkout',
      body: {'requestId': requestId, 'expectedTotal': expectedTotal},
    );
    return [
      for (final item in data['orders'] as List)
        Order.fromJson(item as Map<String, dynamic>),
    ];
  }
}
