import '../../../core/network/api_client.dart';
import '../../listings/domain/listing.dart';
import '../domain/order.dart';

class OrderPage {
  const OrderPage({required this.orders, required this.hasMore});

  final List<Order> orders;
  final bool hasMore;
}

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

  Future<OrderPage> fetchOrders({
    OrderTab tab = OrderTab.all,
    int page = 1,
  }) async {
    final data = await api.get('/api/orders?tab=${tab.name}&page=$page');
    return OrderPage(
      orders: [
        for (final item in data['orders'] as List? ?? const [])
          Order.fromJson(item as Map<String, dynamic>),
      ],
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  Future<Order> fetchOrder(String id) async {
    final data = await api.get('/api/orders/$id');
    return Order.fromJson(data['order'] as Map<String, dynamic>);
  }

  Future<List<Listing>> fetchOrderAgain() async {
    final data = await api.get('/api/orders/again');
    return [
      for (final item in data['listings'] as List? ?? const [])
        Listing.fromJson(item as Map<String, dynamic>),
    ];
  }
}
