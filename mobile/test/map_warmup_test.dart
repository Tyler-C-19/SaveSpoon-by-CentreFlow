import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:savespoon/features/seller_profile/data/map_warmup.dart';

class FakeAndroidMaps extends GoogleMapsFlutterAndroid {
  FakeAndroidMaps({this.fails = false});

  final bool fails;
  int calls = 0;

  @override
  Future<void> warmup() async {
    calls++;
    if (fails) throw Exception('no map');
  }
}

void main() {
  final original = GoogleMapsFlutterPlatform.instance;
  tearDown(() => GoogleMapsFlutterPlatform.instance = original);

  test('warms up the map on Android', () async {
    final maps = FakeAndroidMaps();
    GoogleMapsFlutterPlatform.instance = maps;

    await warmUpMaps();

    expect(maps.calls, 1);
  });

  test('a failed warm-up does not stop the app', () async {
    final maps = FakeAndroidMaps(fails: true);
    GoogleMapsFlutterPlatform.instance = maps;

    await warmUpMaps();

    expect(maps.calls, 1);
  });
}
