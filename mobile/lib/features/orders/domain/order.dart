enum OrderTab {
  all('All'),
  upcoming('Upcoming'),
  history('History'),
  cancelled('Cancelled');

  const OrderTab(this.label);

  final String label;
}

// What the customer sees on the status chip.
enum OrderStage { pending, confirmed, completed, cancelled, pickupEnded }

enum CancelReason {
  changedMind('changed_mind', 'Changed My Mind'),
  orderedByMistake('ordered_by_mistake', 'Ordered by Mistake'),
  cannotMakePickup('cannot_make_pickup', "Can't Make the Pickup Time"),
  other('other', 'Other');

  const CancelReason(this.value, this.label);

  final String value;
  final String label;
}

// Another open order from the same checkout, shown when cancelling.
class CheckoutItem {
  const CheckoutItem({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.stallName,
    required this.canCancel,
  });

  factory CheckoutItem.fromJson(Map<String, dynamic> json) => CheckoutItem(
    id: json['_id'] as String,
    itemName: json['itemName'] as String,
    quantity: json['quantity'] as int,
    stallName: json['stallName'] as String,
    canCancel: json['canCancel'] as bool? ?? false,
  );

  final String id;
  final String itemName;
  final int quantity;
  final String stallName;
  final bool canCancel;
}

class Order {
  const Order({
    required this.id,
    required this.itemName,
    required this.stallName,
    required this.quantity,
    required this.totalPrice,
    required this.pickupStart,
    required this.pickupEnd,
    required this.status,
    this.unitPrice,
    this.createdAt,
    this.checkoutId,
    this.cancelledAt,
    this.cancelUntil,
    this.otherCancellable = 0,
    this.checkoutOrders = const [],
    this.pickupAddress,
    this.category,
    this.imageThumbUrl,
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['_id'] as String,
    itemName: json['itemName'] as String,
    stallName: json['stallName'] as String,
    pickupAddress: json['pickupAddress'] as String?,
    category: json['category'] as String?,
    imageThumbUrl: json['imageThumbUrl'] as String?,
    quantity: json['quantity'] as int,
    unitPrice: (json['unitPrice'] as num?)?.toDouble(),
    totalPrice: (json['totalPrice'] as num).toDouble(),
    pickupStart: DateTime.parse(json['pickupStart'] as String).toLocal(),
    pickupEnd: DateTime.parse(json['pickupEnd'] as String).toLocal(),
    status: json['status'] as String,
    createdAt: _date(json['createdAt']),
    checkoutId: json['checkoutId'] as String?,
    cancelledAt: _date(json['cancelledAt']),
    cancelUntil: _date(json['cancelUntil']),
    otherCancellable: json['otherCancellable'] as int? ?? 0,
    checkoutOrders: [
      for (final item in json['checkoutOrders'] as List? ?? const [])
        CheckoutItem.fromJson(item as Map<String, dynamic>),
    ],
  );

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  final String id;
  final String itemName;
  final String stallName;
  final String? pickupAddress;
  final String? category;
  final String? imageThumbUrl;
  final int quantity;
  final double? unitPrice;
  final double totalPrice;
  final DateTime pickupStart;
  final DateTime pickupEnd;
  final String status;
  final DateTime? createdAt;
  final String? checkoutId;
  final DateTime? cancelledAt;
  // Sent with a single order only; null when it can't be cancelled.
  final DateTime? cancelUntil;
  final int otherCancellable;
  final List<CheckoutItem> checkoutOrders;

  bool get isOpen => status == 'pending' || status == 'confirmed';

  bool canCancelAt(DateTime now) {
    final until = cancelUntil;
    return isOpen && until != null && now.isBefore(until);
  }

  // Shown while pickup is running and cancelling has closed; finished and
  // ended orders show nothing.
  String? cancelClosedReason(DateTime now) {
    if (!isOpen || canCancelAt(now) || !pickupEnd.isAfter(now)) return null;
    return 'Pickup has started, so this order can no longer be cancelled.';
  }

  // A pending or confirmed order whose pickup window has passed shows as
  // Pickup Ended until vendors can mark orders collected.
  OrderStage stageAt(DateTime now) {
    switch (status) {
      case 'completed':
        return OrderStage.completed;
      case 'cancelled':
        return OrderStage.cancelled;
    }
    if (!pickupEnd.isAfter(now)) return OrderStage.pickupEnded;
    return status == 'confirmed' ? OrderStage.confirmed : OrderStage.pending;
  }
}
