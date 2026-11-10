import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const int recentSearchLimit = 6;

List<String> withRecentSearch(List<String> recent, String keyword) {
  final term = keyword.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (term.isEmpty) return recent;
  return [
    term,
    ...recent.where((item) => item.toLowerCase() != term.toLowerCase()),
  ].take(recentSearchLimit).toList();
}

abstract class RecentSearchStore {
  Future<List<String>> read(String accountId);
  Future<void> write(String accountId, List<String> searches);
}

// Kept on the phone only, per account.
class SecureRecentSearchStore implements RecentSearchStore {
  const SecureRecentSearchStore();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _key(String accountId) => 'recent_searches_$accountId';

  @override
  Future<List<String>> read(String accountId) async {
    final saved = await _storage.read(key: _key(accountId));
    if (saved == null) return const [];
    return [for (final item in jsonDecode(saved) as List) item as String];
  }

  @override
  Future<void> write(String accountId, List<String> searches) =>
      _storage.write(key: _key(accountId), value: jsonEncode(searches));
}
