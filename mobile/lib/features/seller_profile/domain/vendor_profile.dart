import 'geo_point.dart';

class VendorProfile {
  const VendorProfile({
    required this.businessName,
    required this.phone,
    required this.address,
    required this.description,
    required this.pin,
    this.placeId,
  });

  factory VendorProfile.fromJson(Map<String, dynamic> json) {
    final coordinates = json['location']['coordinates'] as List;
    return VendorProfile(
      businessName: json['stallName'] as String,
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      description: json['description'] as String? ?? '',
      // Stored as [lng, lat].
      pin: GeoPoint(
        (coordinates[1] as num).toDouble(),
        (coordinates[0] as num).toDouble(),
      ),
      placeId: json['placeId'] as String?,
    );
  }

  final String businessName;
  final String phone;
  final String address;
  final String description;
  final GeoPoint pin;
  final String? placeId;
}
