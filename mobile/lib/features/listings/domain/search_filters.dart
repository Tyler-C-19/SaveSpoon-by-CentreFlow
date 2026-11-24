import 'listing.dart';

enum SearchSort {
  bestMatch('best', 'Best Match'),
  newest('newest', 'Newest'),
  priceLowToHigh('price_asc', 'Price: Low to High'),
  priceHighToLow('price_desc', 'Price: High to Low'),
  endingSoon('ending', 'Ending Soon'),
  mostSold('sold', 'Most Sold'),
  biggestSaving('saving', 'Biggest Saving');

  const SearchSort(this.value, this.label);

  final String value;
  final String label;
}

class SearchFilters {
  const SearchFilters({
    this.categories = const {},
    this.halalOnly = false,
    this.maxPrice,
    this.avoid = const {},
    this.favouritesOnly = false,
    this.openNow = false,
    this.sort,
  });

  static const SearchFilters none = SearchFilters();

  // The Max Price slider runs from 1 to 20; its far end means any price.
  static const double lowestMaxPrice = 1;
  static const double highestMaxPrice = 20;

  final Set<String> categories;
  final bool halalOnly;
  final double? maxPrice;
  final Set<String> avoid;
  final bool favouritesOnly;
  final bool openNow;
  // Empty means the default: Best Match with a keyword, Newest without.
  final SearchSort? sort;

  bool get hasFilters =>
      categories.isNotEmpty ||
      halalOnly ||
      maxPrice != null ||
      avoid.isNotEmpty ||
      favouritesOnly ||
      openNow;

  bool get isEmpty => !hasFilters && sort == null;

  // One for every chip under the search box.
  int get activeCount =>
      categories.length +
      avoid.length +
      (halalOnly ? 1 : 0) +
      (maxPrice != null ? 1 : 0) +
      (favouritesOnly ? 1 : 0) +
      (openNow ? 1 : 0) +
      (sort != null ? 1 : 0);

  SearchSort sortFor({required bool hasKeyword}) =>
      sort ?? (hasKeyword ? SearchSort.bestMatch : SearchSort.newest);

  // Best Match needs a keyword, so without one it falls back to the default.
  SearchFilters forKeyword({required bool hasKeyword}) =>
      !hasKeyword && sort == SearchSort.bestMatch ? copyWith(sort: null) : this;

  Map<String, String> toQuery() => {
    if (categories.isNotEmpty)
      'category': ListingOptions.categories
          .where(categories.contains)
          .join(','),
    if (halalOnly) 'halal': '1',
    if (maxPrice != null) 'maxPrice': maxPrice!.toStringAsFixed(2),
    if (avoid.isNotEmpty)
      'avoid': ListingOptions.allergens.where(avoid.contains).join(','),
    if (favouritesOnly) 'favourites': '1',
    if (openNow) 'openNow': '1',
    if (sort != null) 'sort': sort!.value,
  };

  static const Object _keep = Object();

  SearchFilters copyWith({
    Set<String>? categories,
    bool? halalOnly,
    Object? maxPrice = _keep,
    Set<String>? avoid,
    bool? favouritesOnly,
    bool? openNow,
    Object? sort = _keep,
  }) => SearchFilters(
    categories: categories ?? this.categories,
    halalOnly: halalOnly ?? this.halalOnly,
    maxPrice: identical(maxPrice, _keep) ? this.maxPrice : maxPrice as double?,
    avoid: avoid ?? this.avoid,
    favouritesOnly: favouritesOnly ?? this.favouritesOnly,
    openNow: openNow ?? this.openNow,
    sort: identical(sort, _keep) ? this.sort : sort as SearchSort?,
  );

  bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      _sameSet(categories, other.categories) &&
      halalOnly == other.halalOnly &&
      maxPrice == other.maxPrice &&
      _sameSet(avoid, other.avoid) &&
      favouritesOnly == other.favouritesOnly &&
      openNow == other.openNow &&
      sort == other.sort;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(categories),
    halalOnly,
    maxPrice,
    Object.hashAllUnordered(avoid),
    favouritesOnly,
    openNow,
    sort,
  );
}
