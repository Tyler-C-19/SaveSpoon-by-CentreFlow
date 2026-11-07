import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/geo_point.dart';

abstract class LocationService {
  Future<GeoPoint?> currentLocation();

  Future<String?> addressAt(GeoPoint point);
}

class DeviceLocationService implements LocationService {
  @override
  Future<GeoPoint?> currentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition();
      return GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Location unavailable: $e');
      return null;
    }
  }

  @override
  Future<String?> addressAt(GeoPoint point) async {
    try {
      final places = await Geocoding().placemarkFromCoordinates(
        point.lat,
        point.lng,
      );
      if (places.isEmpty) return null;
      final place = places.first;
      final parts = <String>[];
      for (final part in [
        place.street,
        place.subLocality,
        place.locality,
        place.postalCode,
        place.administrativeArea,
      ]) {
        final text = part?.trim() ?? '';
        if (text.isNotEmpty && !parts.contains(text)) parts.add(text);
      }
      return parts.isEmpty ? null : parts.join(', ');
    } catch (e) {
      debugPrint('Address lookup unavailable: $e');
      return null;
    }
  }
}
