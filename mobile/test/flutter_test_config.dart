import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:savespoon/features/listings/presentation/widgets/listing_image.dart';

// Tests have no phone storage, so listing photos load without the phone cache.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  listingPhotoProvider = NetworkImage.new;
  await testMain();
}
