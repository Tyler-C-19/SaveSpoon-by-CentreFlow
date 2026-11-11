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

class ListingPage {
  const ListingPage({required this.listings, required this.hasMore});

  final List<Listing> listings;
  final bool hasMore;
}

class ListingRepository {
  ListingRepository(this.api);

  final ApiClient api;

  List<Listing> _parseListings(dynamic data) => [
    for (final item in data['listings'] as List? ?? const [])
      Listing.fromJson(item as Map<String, dynamic>),
  ];

  Future<ListingPage> fetchAvailable({int page = 1}) async {
    final data = await api.get('/api/listings?page=$page');
    return ListingPage(
      listings: _parseListings(data),
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  Future<List<Listing>> fetchRunningOut() async =>
      _parseListings(await api.get('/api/listings/running-out'));

  Future<Listing> fetchDetails(String id) async {
    final data = await api.get('/api/listings/$id');
    return Listing.fromJson(data['listing'] as Map<String, dynamic>);
  }

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
