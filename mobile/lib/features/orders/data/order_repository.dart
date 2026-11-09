import '../../../core/network/api_client.dart';
import '../domain/order.dart';

class OrderRepository {
  OrderRepository(this.api);

  final ApiClient api;

  Future<Order> place({
    required String listingId,
    required int quantity,
    required String requestId,
  }) async {
    final data = await api.post(
      '/api/orders',
      body: {
        'listingId': listingId,
        'quantity': quantity,
        'requestId': requestId,
      },
    );
    return Order.fromJson(data['order'] as Map<String, dynamic>);
  }
}
