// Keep in sync with backend listingOptions.js.
abstract final class ListingOptions {
  static const List<String> categories = [
    'Rice',
    'Noodles',
    'Desserts',
    'Snacks',
    'Drinks',
    'Other',
  ];

  static const List<String> allergens = [
    'egg',
    'milk',
    'gluten',
    'soy',
    'peanut',
    'fish',
    'shellfish',
    'sesame',
    'coconut',
    'belacan',
  ];

  static const int lowStockLimit = 5;
  static const Duration endingSoonWindow = Duration(hours: 1);
  static const Duration newWindow = Duration(hours: 1);
}

enum ListingBadge { lowStock, endingSoon, isNew }

String allergenLabel(String value) =>
    '${value[0].toUpperCase()}${value.substring(1)}';

String moneyLabel(double value) => 'RM ${value.toStringAsFixed(2)}';

class Listing {
  const Listing({
    required this.id,
    required this.title,
    required this.originalPrice,
    required this.discountedPrice,
    required this.quantityAvailable,
    required this.pickupStart,
    required this.pickupEnd,
    required this.allergens,
    required this.otherAllergens,
    required this.status,
    this.description,
    this.category,
    this.isHalal,
    this.stallName,
    this.createdAt,
  });

  factory Listing.fromJson(Map<String, dynamic> json) => Listing(
    id: json['_id'] as String,
    title: json['title'] as String,
    description: json['description'] as String?,
    category: json['category'] as String?,
    isHalal: json['isHalal'] as bool?,
    originalPrice: (json['originalPrice'] as num).toDouble(),
    discountedPrice: (json['discountedPrice'] as num).toDouble(),
    quantityAvailable: json['quantityAvailable'] as int,
    pickupStart: DateTime.parse(json['pickupStart'] as String).toLocal(),
    pickupEnd: DateTime.parse(json['pickupEnd'] as String).toLocal(),
    allergens: [for (final item in json['allergens'] as List) item as String],
    otherAllergens: [
      for (final item in json['otherAllergens'] as List? ?? const [])
        item as String,
    ],
    status: json['status'] as String,
    stallName: json['stallName'] as String?,
    createdAt: json['createdAt'] == null
        ? null
        : DateTime.parse(json['createdAt'] as String).toLocal(),
  );

  final String id;
  final String title;
  final String? description;
  final String? category;
  final bool? isHalal;
  final double originalPrice;
  final double discountedPrice;
  final int quantityAvailable;
  final DateTime pickupStart;
  final DateTime pickupEnd;
  final List<String> allergens;
  final List<String> otherAllergens;
  final String status;
  final String? stallName;
  final DateTime? createdAt;

  int get savePercent =>
      ((originalPrice - discountedPrice) / originalPrice * 100).round();

  ListingBadge? badgeAt(DateTime time) {
    if (!isAvailableAt(time)) return null;
    if (isLowStock) return ListingBadge.lowStock;
    if (pickupEnd.difference(time) <= ListingOptions.endingSoonWindow) {
      return ListingBadge.endingSoon;
    }
    final created = createdAt;
    if (created != null &&
        time.difference(created) <= ListingOptions.newWindow) {
      return ListingBadge.isNew;
    }
    return null;
  }

  String? unlistedLabelAt(DateTime time) {
    if (isAvailableAt(time)) return null;
    if (quantityAvailable <= 0 || status == 'sold_out') {
      return 'Unlisted - No Stock';
    }
    if (!pickupEnd.isAfter(time)) return 'Unlisted - Pickup Ended';
    return 'Unlisted';
  }

  bool isAvailableAt(DateTime time) =>
      status == 'active' && quantityAvailable > 0 && pickupEnd.isAfter(time);

  bool get isLowStock =>
      quantityAvailable > 0 &&
      quantityAvailable <= ListingOptions.lowStockLimit;

  String get lowStockLabel => 'Only $quantityAvailable left!';

  String get allergenSummary {
    final names = [...allergens.map(allergenLabel), ...otherAllergens];
    return names.isEmpty ? 'None declared' : names.join(', ');
  }
}
