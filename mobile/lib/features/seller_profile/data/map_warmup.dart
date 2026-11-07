import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

const Duration _timeLimit = Duration(seconds: 2);

Future<void> warmUpMaps() async {
  try {
    final maps = GoogleMapsFlutterPlatform.instance;
    if (maps is GoogleMapsFlutterAndroid) {
      await maps.warmup().timeout(_timeLimit);
    }
  } catch (e) {
    debugPrint('Map warm-up skipped: $e');
  }
}
