import '../../../core/network/api_client.dart';
import '../domain/listing.dart';

class AllergenSuggestion {
  const AllergenSuggestion({
    required this.allergens,
    required this.otherAllergens,
  });

  final List<String> allergens;
  final List<String> otherAllergens;
}

class ListingRepository {
  ListingRepository(this.api);

  final ApiClient api;

  Future<Listing> create({
    required String title,
    required String description,
    required String category,
    required bool isHalal,
    required double originalPrice,
    required double discountedPrice,
    required int quantityAvailable,
    required DateTime pickupStart,
    required DateTime pickupEnd,
    required List<String> allergens,
    required List<String> otherAllergens,
  }) async {
    final data = await api.post(
      '/api/listings',
      body: {
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'category': category,
        'isHalal': isHalal,
        'originalPrice': originalPrice,
        'discountedPrice': discountedPrice,
        'quantityAvailable': quantityAvailable,
        'pickupStart': pickupStart.toUtc().toIso8601String(),
        'pickupEnd': pickupEnd.toUtc().toIso8601String(),
        'allergens': allergens,
        'otherAllergens': otherAllergens,
      },
    );
    return Listing.fromJson(data['listing'] as Map<String, dynamic>);
  }

  Future<List<Listing>> fetchMine() async {
    final data = await api.get('/api/listings/mine');
    return [
      for (final item in data['listings'] as List)
        Listing.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<AllergenSuggestion> suggestAllergens({
    required String title,
    required String description,
  }) async {
    final data = await api.post(
      '/api/listings/allergen-suggestions',
      body: {
        'title': title,
        if (description.isNotEmpty) 'description': description,
      },
    );
    return AllergenSuggestion(
      allergens: [for (final item in data['allergens'] as List) item as String],
      otherAllergens: [
        for (final item in data['otherAllergens'] as List? ?? const [])
          item as String,
      ],
    );
  }
}
