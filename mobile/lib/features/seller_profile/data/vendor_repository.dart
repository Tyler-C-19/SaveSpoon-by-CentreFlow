import '../../../core/network/api_client.dart';
import '../domain/geo_point.dart';

class PlaceSuggestion {
  const PlaceSuggestion({required this.placeId, required this.text});

  final String placeId;
  final String text;
}

class VendorRepository {
  VendorRepository(this.api);

  final ApiClient api;

  Future<void> createProfile({
    required String businessName,
    required String phone,
    required String address,
    required String description,
    required GeoPoint pin,
    String? placeId,
  }) => api.post(
    '/api/vendors/me',
    body: {
      'stallName': businessName,
      'phone': phone,
      'address': address,
      if (description.isNotEmpty) 'description': description,
      'location': pin.toGeoJson(),
      'placeId': ?placeId,
    },
  );

  Future<String> fetchDescription() async {
    final data = await api.get('/api/vendors/me');
    return data['vendor']['description'] as String? ?? '';
  }

  Future<void> updateDescription(String description) =>
      api.patch('/api/vendors/me', body: {'description': description});

  Future<List<PlaceSuggestion>> searchPlaces(
    String query,
    String sessionToken,
  ) async {
    final q = Uri.encodeQueryComponent(query);
    final data = await api.get(
      '/api/places/suggestions?q=$q&sessionToken=$sessionToken',
    );
    return [
      for (final item in data['suggestions'] as List)
        PlaceSuggestion(
          placeId: item['placeId'] as String,
          text: item['text'] as String,
        ),
    ];
  }

  Future<GeoPoint> placeLocation(String placeId, String sessionToken) async {
    final id = Uri.encodeComponent(placeId);
    final data = await api.get(
      '/api/places/$id/location?sessionToken=$sessionToken',
    );
    final location = data['location'];
    return GeoPoint(
      (location['lat'] as num).toDouble(),
      (location['lng'] as num).toDouble(),
    );
  }
}
