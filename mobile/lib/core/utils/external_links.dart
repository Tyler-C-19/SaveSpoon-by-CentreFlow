import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const String mapsFailed = "Couldn't open maps.";
// The button that opens Google Maps directions to a stall.
const String directionsLabel = 'Directions';
const IconData directionsIcon = Icons.directions;
const String phoneFailed = "Couldn't open the phone app.";

typedef LinkOpener = Future<bool> Function(Uri uri);

abstract final class ExternalLinks {
  // Tests swap this so no real app opens.
  static LinkOpener opener = _launch;

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

// Opens in the Google Maps app, or the browser when Maps isn't installed.
// A Google place shows by its address; a hand-placed pin keeps its exact spot.
Uri directionsUri({
  required double lat,
  required double lng,
  String? placeId,
  String? address,
}) {
  final named = placeId != null && address != null && address.isNotEmpty;
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': named ? address : '$lat,$lng',
    'destination_place_id': ?placeId,
  });
}

// Opens the dialer with the number filled in; nothing is called.
Uri phoneUri(String phone) =>
    Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), ''));

// Without a [context] the caller shows the failure itself, for example
// inside a bottom sheet that would cover a snackbar.
Future<bool> openDirections({
  required double lat,
  required double lng,
  String? placeId,
  String? address,
  BuildContext? context,
}) => _open(
  directionsUri(lat: lat, lng: lng, placeId: placeId, address: address),
  mapsFailed,
  context,
);

Future<bool> callPhone(String phone, {BuildContext? context}) =>
    _open(phoneUri(phone), phoneFailed, context);

Future<bool> _open(Uri uri, String failed, BuildContext? context) async {
  final messenger = context == null ? null : ScaffoldMessenger.maybeOf(context);
  final opened = await ExternalLinks.opener(uri);
  if (!opened) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(failed)));
  }
  return opened;
}
