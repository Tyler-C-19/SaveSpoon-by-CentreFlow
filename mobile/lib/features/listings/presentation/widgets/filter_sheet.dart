import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../map/data/position_source.dart';
import '../../../map/presentation/providers/user_location_provider.dart';
import '../../../map/presentation/widgets/location_note.dart';
import '../../domain/listing.dart';
import '../../domain/search_filters.dart';
import 'icon_scale.dart';

const String allergenNote =
    'Based on what vendors declare. Check Food Details.';

String maxPriceLabel(double? price) =>
    price == null ? 'Any Price' : 'Up to ${moneyLabel(price)}';

// Returns the new filters, or null when closed without applying.
Future<SearchFilters?> showFilterSheet(
  BuildContext context, {
  required SearchFilters current,
  required bool hasKeyword,
  bool showSort = true,
}) => showModalBottomSheet<SearchFilters>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) =>
      FilterSheet(current: current, hasKeyword: hasKeyword, showSort: showSort),
);

class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.current,
    required this.hasKeyword,
    this.showSort = true,
  });

  // The sheet never covers more than this share of the screen; it scrolls inside.
  static const double maxShare = 0.6;

  final SearchFilters current;
  final bool hasKeyword;
  // The map has no order, so its sheet leaves out Sort By.
  final bool showSort;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late SearchFilters _draft = widget.current.forKeyword(
    hasKeyword: widget.hasKeyword,
  );

  SearchSort get _defaultSort =>
      widget.hasKeyword ? SearchSort.bestMatch : SearchSort.newest;

  void _update(SearchFilters next) => setState(() => _draft = next);

  bool _nearestBlocked = false;
  bool _locating = false;

  static const String noFix = "Couldn't find your location. Try again.";

  // Nearest needs the customer's location, so picking it asks for it.
  Future<void> _pickNearest(UserLocationProvider location) async {
    if (location.position == null) {
      setState(() => _locating = true);
      await location.requestAndLocate();
      if (!mounted) return;
      setState(() => _locating = false);
    }
    if (location.position == null) {
      setState(() => _nearestBlocked = true);
      return;
    }
    setState(() => _nearestBlocked = false);
    _update(_draft.copyWith(sort: SearchSort.nearest));
  }

  Set<String> _toggled(Set<String> values, String value) =>
      values.contains(value)
      ? ({...values}..remove(value))
      : {...values, value};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.current.forKeyword(hasKeyword: widget.hasKeyword);
    final changed = _draft != current;
    final location = context.watch<UserLocationProvider?>();
    final sorts = [
      for (final sort in SearchSort.values)
        if ((sort != SearchSort.bestMatch || widget.hasKeyword) &&
            (sort != SearchSort.nearest || location != null))
          sort,
    ];
    final selectedSort = _draft.sortFor(hasKeyword: widget.hasKeyword);
    final price = _draft.maxPrice ?? SearchFilters.highestMaxPrice;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * FilterSheet.maxShare,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              'Filter and Sort',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('filter-sheet-scroll'),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showSort) ...[
                    const _Heading('Sort By'),
                    _Chips(
                      children: [
                        for (final sort in sorts)
                          ChoiceChip(
                            key: ValueKey('sort-${sort.value}'),
                            label: Text(sort.label),
                            selected: sort == selectedSort,
                            onSelected: _locating
                                ? null
                                : (_) => sort == SearchSort.nearest
                                      ? _pickNearest(location!)
                                      : _update(
                                          _draft.copyWith(
                                            sort: sort == _defaultSort
                                                ? null
                                                : sort,
                                          ),
                                        ),
                          ),
                      ],
                    ),
                    if (_nearestBlocked && location != null)
                      location.access == LocationAccess.allowed
                          ? Padding(
                              key: const ValueKey('nearest-no-fix'),
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: Text(
                                noFix,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            )
                          : const LocationNote(
                              padding: EdgeInsets.only(top: AppSpacing.xs),
                            ),
                  ],
                  const _Heading('Category'),
                  _Chips(
                    children: [
                      for (final category in ListingOptions.categories)
                        FilterChip(
                          key: ValueKey('filter-category-$category'),
                          label: Text(category),
                          selected: _draft.categories.contains(category),
                          onSelected: (_) => _update(
                            _draft.copyWith(
                              categories: _toggled(_draft.categories, category),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const _Heading('Show Only'),
                  _Chips(
                    children: [
                      FilterChip(
                        key: const ValueKey('filter-halal'),
                        label: const Text('Halal Only'),
                        selected: _draft.halalOnly,
                        onSelected: (value) =>
                            _update(_draft.copyWith(halalOnly: value)),
                      ),
                      FilterChip(
                        key: const ValueKey('filter-favourites'),
                        label: const Text('Favourites'),
                        selected: _draft.favouritesOnly,
                        onSelected: (value) =>
                            _update(_draft.copyWith(favouritesOnly: value)),
                      ),
                      FilterChip(
                        key: const ValueKey('filter-open-now'),
                        label: const Text('Pickup Open Now'),
                        selected: _draft.openNow,
                        onSelected: (value) =>
                            _update(_draft.copyWith(openNow: value)),
                      ),
                    ],
                  ),
                  _Heading('Max Price: ${maxPriceLabel(_draft.maxPrice)}'),
                  Slider(
                    key: const ValueKey('filter-max-price'),
                    value: price,
                    min: SearchFilters.lowestMaxPrice,
                    max: SearchFilters.highestMaxPrice,
                    divisions:
                        (SearchFilters.highestMaxPrice -
                                SearchFilters.lowestMaxPrice)
                            .round(),
                    label: maxPriceLabel(_draft.maxPrice),
                    onChanged: (value) => _update(
                      _draft.copyWith(
                        maxPrice: value >= SearchFilters.highestMaxPrice
                            ? null
                            : value,
                      ),
                    ),
                  ),
                  const _Heading('Avoid Allergens'),
                  _Chips(
                    children: [
                      for (final allergen in ListingOptions.allergens)
                        FilterChip(
                          key: ValueKey('filter-avoid-$allergen'),
                          label: Text(allergenLabel(allergen)),
                          selected: _draft.avoid.contains(allergen),
                          onSelected: (_) => _update(
                            _draft.copyWith(
                              avoid: _toggled(_draft.avoid, allergen),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16 * iconScale(context),
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          allergenNote,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('filter-reset'),
                    onPressed: _draft.isEmpty
                        ? null
                        : () => _update(SearchFilters.none),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('filter-apply'),
                    onPressed: changed
                        ? () => Navigator.of(context).pop(_draft)
                        : null,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: children,
    );
  }
}
