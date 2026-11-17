import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:savespoon/core/network/api_client.dart';
import 'package:savespoon/features/orders/data/order_repository.dart';
import 'package:savespoon/features/orders/domain/order.dart';
import 'package:savespoon/features/orders/presentation/widgets/order_card.dart'
    show collapsibleDateBuckets, dateBucketLabel;

import 'helpers.dart';

Map<String, dynamic> orderJson({
  String id = 'o1',
  String status = 'pending',
  DateTime? pickupEnd,
}) {
  final end = pickupEnd ?? DateTime.now().add(const Duration(hours: 2));
  return {
    '_id': id,
    'itemName': 'Nasi Lemak',
    'stallName': 'Warung Pak Din',
    'pickupAddress': 'Arked Meranti',
    'category': 'Rice',
    'quantity': 2,
    'unitPrice': 4.5,
    'totalPrice': 9,
    'pickupStart': end
        .subtract(const Duration(hours: 2))
        .toUtc()
        .toIso8601String(),
    'pickupEnd': end.toUtc().toIso8601String(),
    'status': status,
    'createdAt': '2026-11-13T02:15:00.000Z',
  };
}

void main() {
  late List<http.Request> requests;

  OrderRepository repositoryAnswering(Object body, [int status = 200]) {
    requests = [];
    return OrderRepository(
      ApiClient(
        client: MockClient((request) async {
          requests.add(request);
          return jsonResponse(body, status);
        }),
      ),
    );
  }

  test('fetchOrders asks for the tab and page and reads the orders', () async {
    final repository = repositoryAnswering({
      'orders': [orderJson()],
      'hasMore': true,
    });

    final page = await repository.fetchOrders(tab: OrderTab.history, page: 3);

    expect(requests.single.url.path, '/api/orders');
    expect(requests.single.url.queryParameters, {
      'tab': 'history',
      'page': '3',
    });
    expect(page.hasMore, isTrue);
    final order = page.orders.single;
    expect(order.unitPrice, 4.5);
    expect(order.totalPrice, 9);
    expect(order.createdAt, DateTime.utc(2026, 11, 13, 2, 15).toLocal());
  });

  test(
    'fetchOrder reads one order and fetchOrderAgain reads listings',
    () async {
      final details = repositoryAnswering({'order': orderJson(id: 'abc')});
      expect((await details.fetchOrder('abc')).id, 'abc');
      expect(requests.single.url.path, '/api/orders/abc');

      final again = repositoryAnswering({
        'listings': [
          {
            '_id': 'l1',
            'title': 'Nasi Lemak',
            'originalPrice': 8,
            'discountedPrice': 4.5,
            'quantityAvailable': 3,
            'pickupStart': '2026-11-13T02:00:00.000Z',
            'pickupEnd': '2026-11-13T04:00:00.000Z',
            'allergens': <String>[],
            'status': 'active',
            'stallName': 'Warung Pak Din',
          },
        ],
      });
      final listings = await again.fetchOrderAgain();
      expect(requests.single.url.path, '/api/orders/again');
      expect(listings.single.stallName, 'Warung Pak Din');
    },
  );

  test('a missing order surfaces the server message', () async {
    final repository = repositoryAnswering({
      'error': "We couldn't find this order.",
    }, 404);

    await expectLater(
      repository.fetchOrder('nope'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          "We couldn't find this order.",
        ),
      ),
    );
  });

  group('stage', () {
    final now = DateTime(2026, 11, 13, 12);

    Order make(String status, {required bool ended}) => Order.fromJson(
      orderJson(
        status: status,
        pickupEnd: now.add(Duration(hours: ended ? -1 : 1)),
      ),
    );

    test('open orders follow their status until pickup ends', () {
      expect(make('pending', ended: false).stageAt(now), OrderStage.pending);
      expect(
        make('confirmed', ended: false).stageAt(now),
        OrderStage.confirmed,
      );
    });

    test('open orders show Pickup Ended once the window has passed', () {
      expect(make('pending', ended: true).stageAt(now), OrderStage.pickupEnded);
      expect(
        make('confirmed', ended: true).stageAt(now),
        OrderStage.pickupEnded,
      );
      expect(
        Order.fromJson(orderJson(pickupEnd: now)).stageAt(now),
        OrderStage.pickupEnded,
      );
    });

    test('completed and cancelled stay as they are', () {
      expect(make('completed', ended: true).stageAt(now), OrderStage.completed);
      expect(
        make('cancelled', ended: false).stageAt(now),
        OrderStage.cancelled,
      );
    });
  });

  group('dateBucketLabel', () {
    final now = DateTime(2026, 11, 14, 9);

    test('names today, yesterday and tomorrow', () {
      expect(dateBucketLabel(now, now), 'Today');
      expect(
        dateBucketLabel(now.subtract(const Duration(days: 1)), now),
        'Yesterday',
      );
      expect(
        dateBucketLabel(now.add(const Duration(days: 1)), now),
        'Tomorrow',
      );
    });

    test('names the rest of a 6-day window This Week either way', () {
      expect(
        dateBucketLabel(now.subtract(const Duration(days: 6)), now),
        'This Week',
      );
      expect(
        dateBucketLabel(now.add(const Duration(days: 6)), now),
        'This Week',
      );
    });

    test('anything further out is Older or Later, and both collapse', () {
      expect(
        dateBucketLabel(now.subtract(const Duration(days: 7)), now),
        'Older',
      );
      expect(dateBucketLabel(now.add(const Duration(days: 7)), now), 'Later');
      expect(collapsibleDateBuckets, {'Older', 'Later'});
      expect(collapsibleDateBuckets.contains('Today'), isFalse);
    });
  });
}
