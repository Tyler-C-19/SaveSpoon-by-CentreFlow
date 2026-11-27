import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../seller_profile/domain/geo_point.dart';
import '../../data/position_source.dart';

// The customer's position for distances and the map. Only asked for on the
// map or for the Nearest sort. Follows the phone while the app is open and
// stops when it goes to the background.
class UserLocationProvider extends ChangeNotifier {
  UserLocationProvider(this.source);

  final PositionSource source;

  LocationAccess _access = LocationAccess.unknown;
  GeoPoint? _position;
  bool _approximate = false;
  bool _started = false;
  bool _disposed = false;
  AppLifecycleListener? _lifecycle;
  StreamSubscription<GeoPoint>? _following;
  Future<void>? _checking;

  LocationAccess get access => _access;
  bool get approximate => _approximate;

  // Null whenever location isn't allowed, so no distance shows.
  GeoPoint? get position =>
      _access == LocationAccess.allowed ? _position : null;

  // Begins following the phone if location is already allowed, and checks
  // again whenever the app comes back to the front.
  void start() {
    if (_started) return;
    _started = true;
    _lifecycle = AppLifecycleListener(
      onResume: refreshIfAllowed,
      onPause: _stopFollowing,
    );
    refreshIfAllowed();
  }

  // Checks without asking; follows the phone only if it is allowed.
  Future<void> refreshIfAllowed() =>
      _checking ??= _refresh().whenComplete(() => _checking = null);

  Future<void> _refresh() async {
    final access = await source.check();
    if (_disposed) return;
    await _apply(access);
  }

  // Shows Android's prompt if it still can, without waiting for a fix; used
  // when the map icon is tapped, before the map opens.
  Future<LocationAccess> askPermission() async {
    await (_checking ?? Future<void>.value());
    final access = await source.request();
    if (_disposed) return access;
    await _apply(access);
    return _access;
  }

  // Finds the position if location is allowed; never asks.
  Future<LocationAccess> locate() async {
    await (_checking ?? Future<void>.value());
    final access = await source.check();
    if (_disposed) return access;
    await _apply(access, needFix: true);
    return _access;
  }

  // Asks for permission if needed, then finds the position.
  Future<LocationAccess> requestAndLocate() async {
    await (_checking ?? Future<void>.value());
    final access = await source.request();
    if (_disposed) return access;
    await _apply(access, needFix: true);
    return _access;
  }

  Future<void> _apply(LocationAccess access, {bool needFix = false}) async {
    if (access != LocationAccess.allowed) {
      _stopFollowing();
      _set(access, _position, _approximate);
      return;
    }
    final approximate = await source.isApproximate();
    var point = await source.lastKnown() ?? _position;
    if (point == null && needFix) point = await source.current();
    if (_disposed) return;
    _set(access, point, approximate);
    _follow();
  }

  void _follow() {
    _following ??= source.watch().listen(
      (point) => _set(_access, point, _approximate),
      onError: (Object e) {
        debugPrint('Location unavailable: $e');
        _stopFollowing();
      },
    );
  }

  void _stopFollowing() {
    _following?.cancel();
    _following = null;
  }

  void _set(LocationAccess access, GeoPoint? point, bool approximate) {
    if (_disposed) return;
    final changed =
        access != _access || point != _position || approximate != _approximate;
    _access = access;
    _position = point;
    _approximate = approximate;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopFollowing();
    _lifecycle?.dispose();
    super.dispose();
  }
}
