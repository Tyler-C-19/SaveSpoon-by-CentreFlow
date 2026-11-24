import '../../listings/domain/listing.dart';
import 'geo_point.dart';

// The server sends coordinates as [lng, lat].
GeoPoint? geoPointFrom(Object? value) {
  if (value is! List || value.length != 2) return null;
  final [lng, lat] = value;
  if (lng is! num || lat is! num) return null;
  return GeoPoint(lat.toDouble(), lng.toDouble());
}

// What customers see about a stall.
class VendorInfo {
  const VendorInfo({
    required this.stallName,
    this.description,
    this.address,
    this.phone,
    this.photoUrl,
    this.location,
    this.placeId,
    this.otherListings = const [],
  });

  factory VendorInfo.fromJson(Map<String, dynamic> json) {
    final vendor = json['vendor'] as Map<String, dynamic>;
    return VendorInfo(
      stallName: vendor['stallName'] as String,
      description: vendor['description'] as String?,
      address: vendor['address'] as String?,
      phone: vendor['phone'] as String?,
      photoUrl: vendor['photoUrl'] as String?,
      location: geoPointFrom(vendor['location']),
      placeId: vendor['placeId'] as String?,
      otherListings: [
        for (final item in json['otherListings'] as List? ?? const [])
          Listing.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  final String stallName;
  final String? description;
  final String? address;
  final String? phone;
  final String? photoUrl;
  final GeoPoint? location;
  final String? placeId;
  // Up to 4 of the stall's other listings on sale now.
  final List<Listing> otherListings;
}
