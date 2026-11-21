enum OrderTab {
  all('All'),
  upcoming('Upcoming'),
  history('History');

  const OrderTab(this.label);

  final String label;
}

// What the customer sees on the status chip.
enum OrderStage { pending, confirmed, completed, cancelled, pickupEnded }

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
    this.pickupAddress,
    this.category,
    this.imageThumbUrl,
    this.unitPrice,
    this.createdAt,
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
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.parse(json['createdAt'] as String).toLocal(),
  );

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
