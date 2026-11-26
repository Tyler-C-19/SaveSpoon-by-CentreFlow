import '../domain/search_filters.dart';

abstract class SearchFilterStore {
  Future<SearchFilters> read(String accountId);
  Future<void> write(String accountId, SearchFilters filters);
}

// Kept per account while the app is open; closing the app resets them.
class SessionSearchFilterStore implements SearchFilterStore {
  const SessionSearchFilterStore();

  static final Map<String, SearchFilters> _saved = {};

  // Forgets every account's filters, as closing the app does.
  static void clear() => _saved.clear();

  @override
  Future<SearchFilters> read(String accountId) async =>
      _saved[accountId] ?? SearchFilters.none;

  @override
  Future<void> write(String accountId, SearchFilters filters) async {
    if (filters.isEmpty) {
      _saved.remove(accountId);
    } else {
      _saved[accountId] = filters;
    }
  }
}
