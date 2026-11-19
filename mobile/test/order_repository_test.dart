import 'dart:convert';

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

  test(
    'cancelOrder sends the reason and reads cancelled and skipped',
    () async {
      final repository = repositoryAnswering({
        'cancelled': [orderJson(id: 'a', status: 'cancelled')],
        'skipped': [orderJson(id: 'b')],
      });

      final result = await repository.cancelOrder(
        'a',
        reason: CancelReason.cannotMakePickup,
        wholeCheckout: true,
      );

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/orders/a/cancel');
      expect(jsonDecode(requests.single.body), {
        'reason': 'cannot_make_pickup',
        'wholeCheckout': true,
      });
      expect(result.cancelled.single.status, 'cancelled');
      expect(result.skipped.single.id, 'b');
    },
  );

  test('cancelOrder leaves out an empty reason and surfaces errors', () async {
    final repository = repositoryAnswering({
      'code': 'PICKUP_STARTED',
      'error': 'Pickup has started, so this order can no longer be cancelled.',
    }, 409);

    await expectLater(
      repository.cancelOrder('a'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.message, 'message', startsWith('Pickup has')),
      ),
    );
    expect(jsonDecode(requests.single.body), {'wholeCheckout': false});
  });

  group('cancelling', () {
    final now = DateTime(2026, 11, 13, 12);

    Order make({
      String status = 'pending',
      DateTime? until,
      DateTime? pickupEnd,
    }) => Order.fromJson({
      ...orderJson(
        status: status,
        pickupEnd: pickupEnd ?? now.add(const Duration(hours: 2)),
      ),
      'cancelUntil': until?.toUtc().toIso8601String(),
      'cancelledAt': status == 'cancelled' ? '2026-11-13T03:00:00.000Z' : null,
      'checkoutId': 'c1',
      'otherCancellable': 1,
      'checkoutOrders': [
        {
          '_id': 'o2',
          'itemName': 'Kuih',
          'quantity': 1,
          'stallName': 'Warung A',
          'canCancel': true,
        },
        {
          '_id': 'o3',
          'itemName': 'Teh Tarik',
          'quantity': 2,
          'stallName': 'Kedai B',
          'canCancel': false,
        },
      ],
    });

    test('an open order can be cancelled until the server\'s time', () {
      final order = make(until: now.add(const Duration(minutes: 1)));
      expect(order.canCancelAt(now), isTrue);
      expect(order.cancelClosedReason(now), isNull);
      expect(order.checkoutId, 'c1');
      expect(order.otherCancellable, 1);
      expect(
        [
          for (final item in order.checkoutOrders)
            '${item.quantity} x ${item.itemName}, ${item.stallName}, '
                '${item.canCancel}',
        ],
        ['1 x Kuih, Warung A, true', '2 x Teh Tarik, Kedai B, false'],
      );
      expect(order.canCancelAt(now.add(const Duration(minutes: 1))), isFalse);
    });

    test(
      'an open order during pickup says why it can no longer be cancelled',
      () {
        expect(
          make().cancelClosedReason(now),
          'Pickup has started, so this order can no longer be cancelled.',
        );
      },
    );

    test('an ended order shows no reason', () {
      expect(
        make(pickupEnd: now.subtract(const Duration(minutes: 1)))
            .cancelClosedReason(now),
        isNull,
      );
    });

    test('finished orders cannot be cancelled and show no reason', () {
      final cancelled = make(status: 'cancelled');
      expect(cancelled.canCancelAt(now), isFalse);
      expect(cancelled.cancelClosedReason(now), isNull);
      expect(cancelled.cancelledAt, DateTime.utc(2026, 11, 13, 3).toLocal());
      expect(make(status: 'completed').cancelClosedReason(now), isNull);
    });
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
