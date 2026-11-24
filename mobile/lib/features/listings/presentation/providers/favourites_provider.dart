import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/favourites_repository.dart';

// The signed-in customer's Favourites, shared by every heart in the app.
class FavouritesProvider extends ChangeNotifier {
  FavouritesProvider(this._repository);

  final FavouritesRepository _repository;

  Set<String> _ids = {};
  String? _accountId;
  Future<void>? _loading;
  int _changes = 0;

  bool isFavourite(String listingId) => _ids.contains(listingId);

  int get count => _ids.length;

  // Goes up whenever a heart changes, so lists of Favourites know to reload.
  int get changes => _changes;

  // Loads once per account; a different account starts again from empty.
  Future<void> ensureLoaded(String accountId) {
    if (_accountId == accountId) return _loading ?? Future.value();
    _accountId = accountId;
    // Pages ask while they build, so the hearts clear just after.
    if (_ids.isNotEmpty) {
      _ids = {};
      scheduleMicrotask(notifyListeners);
    }
    return _loading = _load(accountId);
  }

  Future<void> _load(String accountId) async {
    try {
      final ids = await _repository.fetchIds();
      if (_accountId != accountId) return;
      _ids = {...ids, ..._ids};
      notifyListeners();
    } catch (_) {
      // Tried again the next time a page asks.
      if (_accountId == accountId) _accountId = null;
    } finally {
      if (_accountId == accountId || _accountId == null) _loading = null;
    }
  }

  // Changes the heart at once and puts it back if saving fails.
  Future<void> toggle(String listingId) async {
    final adding = !_ids.contains(listingId);
    _set(listingId, adding);
    try {
      if (adding) {
        await _repository.add(listingId);
      } else {
        await _repository.remove(listingId);
      }
    } catch (_) {
      _set(listingId, !adding);
      rethrow;
    }
  }

  void _set(String listingId, bool favourite) {
    _ids = {..._ids};
    if (favourite) {
      _ids.add(listingId);
    } else {
      _ids.remove(listingId);
    }
    _changes++;
    notifyListeners();
  }
}
