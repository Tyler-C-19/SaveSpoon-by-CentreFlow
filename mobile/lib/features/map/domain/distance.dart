import 'dart:math' as math;

import '../../seller_profile/domain/geo_point.dart';

const double _earthRadiusMetres = 6371000;
const double _farMetres = 20000;

// Straight-line distance over the earth's surface.
double metresBetween(GeoPoint from, GeoPoint to) {
  double radians(double degrees) => degrees * math.pi / 180;
  final dLat = radians(to.lat - from.lat);
  final dLng = radians(to.lng - from.lng);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(radians(from.lat)) *
          math.cos(radians(to.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusMetres * math.asin(math.min(1, math.sqrt(a)));
}

// "350 m", "1.2 km" or "20+ km".
String distanceLabel(double metres) {
  final tens = math.max(10, (metres / 10).round() * 10);
  if (tens < 1000) return '$tens m';
  if (metres >= _farMetres) return '20+ km';
  return '${(metres / 1000).toStringAsFixed(1)} km';
}

// Null when either point is unknown.
String? distanceBetween(GeoPoint? from, GeoPoint? to) =>
    from == null || to == null ? null : distanceLabel(metresBetween(from, to));
