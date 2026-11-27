import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../seller_profile/domain/geo_point.dart';

enum LocationAccess { unknown, allowed, denied, deniedForever, serviceOff }

abstract class PositionSource {
  // Checks without asking the customer.
  Future<LocationAccess> check();

  // Shows Android's permission prompt when it still can.
  Future<LocationAccess> request();

  Future<GeoPoint?> current();

  // The phone's most recent position, returned at once; may be old or null.
  Future<GeoPoint?> lastKnown();

  // New positions as the phone moves.
  Stream<GeoPoint> watch();

  // True when the customer allowed only approximate location.
  Future<bool> isApproximate();

  Future<void> openAppSettings();

  Future<void> openLocationSettings();
}

class DevicePositionSource implements PositionSource {
  static const Duration _timeLimit = Duration(seconds: 15);
  // Moves shorter than this don't update distances.
  static const int _minMoveMetres = 20;

  LocationAccess _accessFrom(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => LocationAccess.allowed,
        LocationPermission.deniedForever => LocationAccess.deniedForever,
        LocationPermission.denied => LocationAccess.denied,
        LocationPermission.unableToDetermine => LocationAccess.unknown,
      };

  Future<LocationAccess> _withService(LocationAccess access) async {
    if (access != LocationAccess.allowed) return access;
    return await Geolocator.isLocationServiceEnabled()
        ? access
        : LocationAccess.serviceOff;
  }

  @override
  Future<LocationAccess> check() async {
    try {
      return await _withService(
        _accessFrom(await Geolocator.checkPermission()),
      );
    } catch (e) {
      debugPrint('Location unavailable: $e');
      return LocationAccess.unknown;
    }
  }

  @override
  Future<LocationAccess> request() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return await _withService(_accessFrom(permission));
    } catch (e) {
      debugPrint('Location unavailable: $e');
      return LocationAccess.unknown;
    }
  }

  @override
  Future<GeoPoint?> current() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: _timeLimit),
      );
      return GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Location unavailable: $e');
      return null;
    }
  }

  @override
  Future<GeoPoint?> lastKnown() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      return position == null
          ? null
          : GeoPoint(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Location unavailable: $e');
      return null;
    }
  }

  @override
  Stream<GeoPoint> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(distanceFilter: _minMoveMetres),
  ).map((position) => GeoPoint(position.latitude, position.longitude));

  @override
  Future<bool> isApproximate() async {
    try {
      return await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
