class CartItem {
  const CartItem({
    required this.listingId,
    required this.itemName,
    required this.stallName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.available,
    required this.notices,
    this.reason,
    this.category,
    this.pickupAddress,
    this.stockLeft,
    this.pickupStart,
    this.pickupEnd,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
    listingId: json['listingId'] as String,
    itemName: json['itemName'] as String,
    stallName: json['stallName'] as String,
    quantity: json['quantity'] as int,
    unitPrice: (json['unitPrice'] as num).toDouble(),
    lineTotal: (json['lineTotal'] as num).toDouble(),
    available: json['available'] as bool,
    reason: json['reason'] as String?,
    notices: [for (final item in json['notices'] as List) item as String],
    category: json['category'] as String?,
    pickupAddress: json['pickupAddress'] as String?,
    stockLeft: json['stockLeft'] as int?,
    pickupStart: json['pickupStart'] == null
        ? null
        : DateTime.parse(json['pickupStart'] as String).toLocal(),
    pickupEnd: json['pickupEnd'] == null
        ? null
        : DateTime.parse(json['pickupEnd'] as String).toLocal(),
  );

  final String listingId;
  final String itemName;
  final String stallName;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final bool available;
  final String? reason;
  final List<String> notices;
  final String? category;
  final String? pickupAddress;
  final int? stockLeft;
  final DateTime? pickupStart;
  final DateTime? pickupEnd;
}

class Cart {
  const Cart({
    required this.items,
    required this.total,
    required this.warnings,
  });

  factory Cart.fromJson(Map<String, dynamic> json) => Cart(
    items: [
      for (final item in json['items'] as List)
        CartItem.fromJson(item as Map<String, dynamic>),
    ],
    total: (json['total'] as num).toDouble(),
    warnings: [for (final item in json['warnings'] as List) item as String],
  );

  final List<CartItem> items;
  final double total;
  final List<String> warnings;

  List<CartItem> get availableItems => [
    for (final item in items)
      if (item.available) item,
  ];

  bool get hasUnavailable => items.any((item) => !item.available);

  Map<String, List<CartItem>> get itemsByStall {
    final groups = <String, List<CartItem>>{};
    for (final item in items) {
      (groups[item.stallName] ??= []).add(item);
    }
    return groups;
  }
}
