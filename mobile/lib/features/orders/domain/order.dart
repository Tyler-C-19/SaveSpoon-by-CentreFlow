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
  });

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['_id'] as String,
    itemName: json['itemName'] as String,
    stallName: json['stallName'] as String,
    pickupAddress: json['pickupAddress'] as String?,
    category: json['category'] as String?,
    quantity: json['quantity'] as int,
    totalPrice: (json['totalPrice'] as num).toDouble(),
    pickupStart: DateTime.parse(json['pickupStart'] as String).toLocal(),
    pickupEnd: DateTime.parse(json['pickupEnd'] as String).toLocal(),
    status: json['status'] as String,
  );

  final String id;
  final String itemName;
  final String stallName;
  final String? pickupAddress;
  final String? category;
  final int quantity;
  final double totalPrice;
  final DateTime pickupStart;
  final DateTime pickupEnd;
  final String status;
}
