import 'package:flutter/foundation.dart';

class ListingChanges extends ChangeNotifier {
  void markChanged() => notifyListeners();
}
