import 'dart:math';

final Random _random = Random.secure();

String newRequestId() => [
  for (var index = 0; index < 32; index++)
    _random.nextInt(16).toRadixString(16),
].join();
