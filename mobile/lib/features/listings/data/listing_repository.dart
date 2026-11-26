import '../../../core/network/api_client.dart';
import '../../profile/domain/photo_crop.dart';
import '../../seller_profile/domain/vendor_info.dart';
import '../domain/listing.dart';
import '../domain/search_filters.dart';
import '../../map/domain/map_stall.dart';
import '../../seller_profile/domain/geo_point.dart';

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

class SearchResults {
  const SearchResults({
    required this.listings,
    required this.hasMore,
    this.otherStalls = const [],
  });

  final List<Listing> listings;
  final bool hasMore;
  final List<Listing> otherStalls;
}

// A vendor's own listing plus the items sold in its earlier rounds.
class OwnListing {
  const OwnListing({
    required this.listing,
    required this.pastSold,
    this.activeOrderCount = 0,
  });

  final Listing listing;
  final int pastSold;
  final int activeOrderCount;

  int get totalSold => pastSold + listing.soldCount;
}

class StockChangedException implements Exception {
  const StockChangedException(this.message, this.current);

  static const String code = 'STOCK_CHANGED';

  final String message;
  final Listing current;
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

  Future<ListingPage> fetchFavourites() async {
    final data = await api.get('/api/listings/favourites');
    return ListingPage(
      listings: _parseListings(data),
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  // The keyword can be left empty once a filter or sort is chosen.
  // [near] is only sent for the Nearest sort.
  Future<SearchResults> search(
    String query, {
    int page = 1,
    SearchFilters filters = SearchFilters.none,
    GeoPoint? near,
  }) async {
    final keyword = query.trim();
    final params = Uri(
      queryParameters: {
        if (keyword.isNotEmpty) 'q': keyword,
        ...filters.forKeyword(hasKeyword: keyword.isNotEmpty).toQuery(),
        ..._nearQuery(near),
        'page': '$page',
      },
    ).query;
    final data = await api.get('/api/listings/search?$params');
    return SearchResults(
      listings: _parseListings(data),
      hasMore: data['hasMore'] as bool? ?? false,
      otherStalls: _parseListings({'listings': data['otherStalls']}),
    );
  }

  // Rounded to about 110 m before it leaves the phone.
  Map<String, String> _nearQuery(GeoPoint? near) => near == null
      ? const {}
      : {
          'lat': near.lat.toStringAsFixed(3),
          'lng': near.lng.toStringAsFixed(3),
        };

  // Stalls with food on sale now, filtered like Search when [filters] or
  // [query] are given.
  Future<List<MapStall>> fetchMap({
    String query = '',
    SearchFilters filters = SearchFilters.none,
  }) async {
    final keyword = query.trim();
    final params = Uri(
      queryParameters: {
        if (keyword.isNotEmpty) 'q': keyword,
        ...filters.copyWith(sort: null).toQuery(),
      },
    ).query;
    final data = await api.get(
      params.isEmpty ? '/api/listings/map' : '/api/listings/map?$params',
    );
    return [
      for (final item in data['stalls'] as List? ?? const [])
        ?MapStall.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Listing> fetchDetails(String id) async {
    final data = await api.get('/api/listings/$id');
    return Listing.fromJson(data['listing'] as Map<String, dynamic>);
  }

  // Vendor info is kept briefly so the pane can open already filled.
  static const Duration vendorInfoFresh = Duration(seconds: 30);
  final Map<String, (DateTime, VendorInfo)> _vendorInfo = {};
  final Map<String, Future<VendorInfo>> _vendorInfoLoading = {};

  // [all] includes the listing itself in the stall's items (from the map).
  String _vendorInfoKey(String listingId, bool all) =>
      all ? '$listingId?all' : listingId;

  VendorInfo? cachedVendorInfo(String listingId, {bool all = false}) =>
      _vendorInfo[_vendorInfoKey(listingId, all)]?.$2;

  bool isVendorInfoFresh(String listingId, {bool all = false}) {
    final saved = _vendorInfo[_vendorInfoKey(listingId, all)];
    return saved != null &&
        DateTime.now().difference(saved.$1) < vendorInfoFresh;
  }

  Future<VendorInfo> fetchVendorInfo(String listingId, {bool all = false}) =>
      _vendorInfoLoading[_vendorInfoKey(listingId, all)] ??= _loadVendorInfo(
        listingId,
        all,
      );

  Future<VendorInfo> _loadVendorInfo(String listingId, bool all) async {
    final key = _vendorInfoKey(listingId, all);
    try {
      final data = await api.get(
        '/api/listings/$listingId/vendor${all ? '?all=1' : ''}',
      );
      final info = VendorInfo.fromJson(data);
      _vendorInfo[key] = (DateTime.now(), info);
      return info;
    } finally {
      _vendorInfoLoading.remove(key);
    }
  }

  // Starts loading early, for example when a card is touched; the pane shows
  // any error itself.
  void prefetchVendorInfo(String listingId, {bool all = false}) {
    if (isVendorInfoFresh(listingId, all: all)) return;
    fetchVendorInfo(listingId, all: all).ignore();
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

  OwnListing _ownListing(dynamic data) => OwnListing(
    listing: Listing.fromJson(data['listing'] as Map<String, dynamic>),
    pastSold: data['pastSold'] as int? ?? 0,
    activeOrderCount: data['activeOrderCount'] as int? ?? 0,
  );

  Future<OwnListing> fetchMineOne(String id) async =>
      _ownListing(await api.get('/api/listings/mine/$id'));

  // Saves the finished round on the server and puts the listing back on sale.
  Future<OwnListing> relist({
    required String id,
    required int quantityAvailable,
    required DateTime pickupStart,
    required DateTime pickupEnd,
    bool paused = false,
  }) async => _ownListing(
    await api.post(
      '/api/listings/$id/relist',
      body: {
        'quantityAvailable': quantityAvailable,
        'pickupStart': pickupStart.toUtc().toIso8601String(),
        'pickupEnd': pickupEnd.toUtc().toIso8601String(),
        'paused': paused,
      },
    ),
  );

  // Sets stock only if it still equals expectedQuantity on the server;
  // otherwise throws StockChangedException with the listing as it is now.
  Future<Listing> updateStock({
    required String id,
    required int quantity,
    required int expectedQuantity,
  }) async {
    try {
      final data = await api.patch(
        '/api/listings/$id/stock',
        body: {'quantity': quantity, 'expectedQuantity': expectedQuantity},
      );
      return Listing.fromJson(data['listing'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.code != StockChangedException.code) rethrow;
      throw StockChangedException(e.message, (await fetchMineOne(id)).listing);
    }
  }

  // Stock changes only if it still equals expectedQuantity on the server;
  // otherwise throws StockChangedException with the listing as it is now.
  Future<Listing> update({
    required String id,
    required String title,
    required String description,
    required String category,
    required bool isHalal,
    required double originalPrice,
    required double discountedPrice,
    required int quantityAvailable,
    required int expectedQuantity,
    required DateTime pickupStart,
    required DateTime pickupEnd,
    required List<String> allergens,
    required List<String> otherAllergens,
  }) async {
    try {
      final data = await api.patch(
        '/api/listings/$id',
        body: {
          'title': title,
          'description': description,
          'category': category,
          'isHalal': isHalal,
          'originalPrice': originalPrice,
          'discountedPrice': discountedPrice,
          'quantityAvailable': quantityAvailable,
          'expectedQuantity': expectedQuantity,
          'pickupStart': pickupStart.toUtc().toIso8601String(),
          'pickupEnd': pickupEnd.toUtc().toIso8601String(),
          'allergens': allergens,
          'otherAllergens': otherAllergens,
        },
      );
      return Listing.fromJson(data['listing'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.code != StockChangedException.code) rethrow;
      throw StockChangedException(e.message, (await fetchMineOne(id)).listing);
    }
  }

  Future<void> delete(String id) => api.delete('/api/listings/$id');

  Listing _listing(dynamic data) =>
      Listing.fromJson(data['listing'] as Map<String, dynamic>);

  Future<Listing> setPhoto(
    String id, {
    required List<int> bytes,
    required String filename,
    required PhotoCrop crop,
  }) async => _listing(
    await api.putFile(
      '/api/listings/$id/photo',
      field: 'photo',
      bytes: bytes,
      filename: filename,
      fields: crop.toFormFields(),
    ),
  );

  Future<Listing> reframePhoto(String id, PhotoCrop crop) async => _listing(
    await api.patch('/api/listings/$id/photo', body: {'crop': crop.toJson()}),
  );

  Future<Listing> removePhoto(String id) async =>
      _listing(await api.delete('/api/listings/$id/photo'));

  Future<Listing> setPaused(String id, {required bool paused}) async {
    final data = await api.patch(
      '/api/listings/$id/availability',
      body: {'paused': paused},
    );
    return Listing.fromJson(data['listing'] as Map<String, dynamic>);
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
