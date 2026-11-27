import '../../listings/domain/listing.dart';
import '../../seller_profile/domain/geo_point.dart';
import '../../seller_profile/domain/vendor_info.dart';

// One map marker: a stall with food on sale now.
class MapStall {
  const MapStall({
    required this.stallName,
    required this.location,
    required this.count,
    required this.listing,
    this.address,
    this.matches = const [],
  });

  // The item used to open the stall's pane.
  final Listing listing;
  final String stallName;
  final String? address;
  final GeoPoint location;
  final int count;
  // The stall's first few items that matched the map's search.
  final List<Listing> matches;

  static MapStall? fromJson(Map<String, dynamic> json) {
    final location = geoPointFrom(json['location']);
    if (location == null) return null;
    return MapStall(
      stallName: json['stallName'] as String? ?? '',
      address: json['address'] as String?,
      location: location,
      count: json['count'] as int? ?? 1,
      listing: Listing.fromJson(json['listing'] as Map<String, dynamic>),
      matches: [
        for (final item in json['matches'] as List? ?? const [])
          Listing.fromJson(item as Map<String, dynamic>),
      ],
    );
  }
}
