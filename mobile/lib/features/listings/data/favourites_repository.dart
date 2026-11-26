import '../../../core/network/api_client.dart';

class FavouritesRepository {
  FavouritesRepository(this.api);

  final ApiClient api;

  Future<List<String>> fetchIds() async {
    final data = await api.get('/api/favourites/ids');
    return [for (final id in data['listingIds'] as List? ?? const []) '$id'];
  }

  // An empty JSON body; the server refuses "null".
  Future<void> add(String listingId) =>
      api.put('/api/favourites/$listingId', body: const {});

  Future<void> remove(String listingId) =>
      api.delete('/api/favourites/$listingId');
}
