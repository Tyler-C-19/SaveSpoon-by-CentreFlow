import 'package:flutter/foundation.dart';

import '../../../../core/network/api_client.dart';
import '../../../orders/domain/order.dart';
import '../../data/cart_repository.dart';
import '../../domain/cart.dart';

class CartProvider extends ChangeNotifier {
  CartProvider(this._repository);

  final CartRepository _repository;

  Cart? _cart;
  String? _error;
  int _generation = 0;

  Cart? get cart => _cart;
  String? get error => _error;
  int get count => _cart?.items.length ?? 0;

  void _set(Cart cart) {
    _cart = cart;
    _error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    final generation = _generation;
    try {
      final cart = await _repository.fetch();
      if (generation == _generation) _set(cart);
    } on ApiException catch (e) {
      if (generation != _generation) return;
      _error = e.message;
      notifyListeners();
    }
  }

  Future<String> addItem(String listingId, int quantity) async {
    final update = await _repository.add(listingId, quantity);
    _set(update.cart);
    return update.message;
  }

  Future<void> setQuantity(String listingId, int quantity) async =>
      _set(await _repository.setQuantity(listingId, quantity));

  Future<void> remove(String listingId) async =>
      _set(await _repository.remove(listingId));

  Future<void> removeUnavailable() async =>
      _set(await _repository.removeUnavailable());

  Future<void> clearItems() async => _set(await _repository.clear());

  Future<List<Order>> checkout({
    required String requestId,
    required double expectedTotal,
  }) =>
      _repository.checkout(requestId: requestId, expectedTotal: expectedTotal);

  void reset() {
    _generation++;
    _cart = null;
    _error = null;
    notifyListeners();
  }
}
