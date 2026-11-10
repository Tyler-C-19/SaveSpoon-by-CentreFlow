import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../domain/geo_point.dart';

typedef PickupMapBuilder =
    Widget Function(
      BuildContext context,
      GeoPoint target,
      GeoPoint? pin,
      ValueChanged<GeoPoint> onTap,
    );

Widget googlePickupMap(
  BuildContext context,
  GeoPoint target,
  GeoPoint? pin,
  ValueChanged<GeoPoint> onTap,
) => GooglePickupMap(target: target, pin: pin, onTap: onTap);

class GooglePickupMap extends StatefulWidget {
  const GooglePickupMap({
    super.key,
    required this.target,
    required this.pin,
    required this.onTap,
  });

  final GeoPoint target;
  final GeoPoint? pin;
  final ValueChanged<GeoPoint> onTap;

  @override
  State<GooglePickupMap> createState() => _GooglePickupMapState();
}

class _GooglePickupMapState extends State<GooglePickupMap> {
  static const double _startZoom = 15;
  static const double _targetZoom = 17;

  GoogleMapController? _controller;

  LatLng _latLng(GeoPoint point) => LatLng(point.lat, point.lng);

  @override
  void didUpdateWidget(GooglePickupMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != oldWidget.target) {
      _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(_latLng(widget.target), _targetZoom),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _latLng(widget.target),
        zoom: _startZoom,
      ),
      onMapCreated: (controller) => _controller = controller,
      onTap: (point) =>
          widget.onTap(GeoPoint(point.latitude, point.longitude)),
      markers: {
        if (pin != null)
          Marker(markerId: const MarkerId('pickup'), position: _latLng(pin)),
      },
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
      },
    );
  }
}
