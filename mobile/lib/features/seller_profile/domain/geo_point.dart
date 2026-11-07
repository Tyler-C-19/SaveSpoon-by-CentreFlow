class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  static const GeoPoint utmSkudai = GeoPoint(1.559, 103.6385);

  final double lat;
  final double lng;

  Map<String, dynamic> toGeoJson() => {
    'type': 'Point',
    'coordinates': [lng, lat],
  };

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}
