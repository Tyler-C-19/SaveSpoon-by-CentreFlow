import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/listing.dart';
import '../../domain/search_filters.dart';
import 'filter_sheet.dart';
import 'icon_scale.dart';

// One removable chip per active filter or chosen sort, under the search box,
// in a single row that scrolls sideways and ends with Clear All.
class ActiveFilterChips extends StatefulWidget {
  const ActiveFilterChips({
    super.key,
    required this.filters,
    required this.hasKeyword,
    required this.onChanged,
  });

  static const double fadeWidth = 24;
  static const Duration leaving = Duration(milliseconds: 200);

  final SearchFilters filters;
  final bool hasKeyword;
  final ValueChanged<SearchFilters> onChanged;

  @override
  State<ActiveFilterChips> createState() => _ActiveFilterChipsState();
}

class _ActiveFilterChipsState extends State<ActiveFilterChips> {
  final ScrollController _scroll = ScrollController();
  bool _moreBefore = false;
  bool _moreAfter = false;
  // Chips fading and closing up before their filter is removed.
  final Set<String> _leaving = {};
  Timer? _remove;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateFades);
  }

  @override
  void didUpdateWidget(ActiveFilterChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filters != widget.filters) _leaving.clear();
  }

  @override
  void dispose() {
    _remove?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _removeChip(Set<String> keys) {
    setState(() => _leaving.addAll(keys));
    _remove?.cancel();
    _remove = Timer(ActiveFilterChips.leaving, () {
      // Several quick taps remove every chip that was tapped; removing them
      // all is the same as Clear All.
      var next = widget.filters.forKeyword(hasKeyword: widget.hasKeyword);
      if (_leaving.containsAll([for (final (key, _, _) in _chips(next)) key])) {
        widget.onChanged(SearchFilters.none);
        return;
      }
      for (final key in _leaving) {
        for (final (chipKey, _, without) in _chips(next)) {
          if (chipKey == key) next = without;
        }
      }
      widget.onChanged(next);
    });
  }

  // Fades an edge only while there are chips hidden past it.
  void _updateFades() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final before = position.pixels > 0;
    final after = position.extentAfter > 0;
    if (before != _moreBefore || after != _moreAfter) {
      setState(() {
        _moreBefore = before;
        _moreAfter = after;
      });
    }
  }

  List<(String, String, SearchFilters)> _chips(SearchFilters shown) => [
    if (shown.sort != null)
      ('sort', shown.sort!.label, shown.copyWith(sort: null)),
    for (final category in ListingOptions.categories)
      if (shown.categories.contains(category))
        (
          'category-$category',
          category,
          shown.copyWith(categories: {...shown.categories}..remove(category)),
        ),
    if (shown.halalOnly)
      ('halal', 'Halal Only', shown.copyWith(halalOnly: false)),
    if (shown.maxPrice != null)
      (
        'max-price',
        maxPriceLabel(shown.maxPrice),
        shown.copyWith(maxPrice: null),
      ),
    for (final allergen in ListingOptions.allergens)
      if (shown.avoid.contains(allergen))
        (
          'avoid-$allergen',
          'Avoid ${allergenLabel(allergen)}',
          shown.copyWith(avoid: {...shown.avoid}..remove(allergen)),
        ),
    if (shown.favouritesOnly)
      ('favourites', 'Favourites', shown.copyWith(favouritesOnly: false)),
    if (shown.openNow)
      ('open-now', 'Pickup Open Now', shown.copyWith(openNow: false)),
  ];

  @override
  Widget build(BuildContext context) {
    final chips = _chips(
      widget.filters.forKeyword(hasKeyword: widget.hasKeyword),
    );
    if (chips.isEmpty) return const SizedBox.shrink();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateFades();
    });

    const fade = ActiveFilterChips.fadeWidth;
    // Clear All stays at the right end, outside the row that scrolls.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: ShaderMask(
              key: const ValueKey('active-filter-row'),
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  _moreBefore ? Colors.transparent : Colors.white,
                  Colors.white,
                  Colors.white,
                  _moreAfter ? Colors.transparent : Colors.white,
                ],
                stops: [
                  0,
                  (fade / bounds.width).clamp(0.0, 0.5),
                  (1 - fade / bounds.width).clamp(0.5, 1.0),
                  1,
                ],
              ).createShader(bounds),
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (key, label, _) in chips)
                      AnimatedSize(
                        key: ValueKey('active-filter-space-$key'),
                        duration: ActiveFilterChips.leaving,
                        child: AnimatedOpacity(
                          duration: ActiveFilterChips.leaving,
                          opacity: _leaving.contains(key) ? 0 : 1,
                          child: _leaving.contains(key)
                              ? const SizedBox(height: kMinInteractiveDimension)
                              : Padding(
                                  padding: const EdgeInsets.only(
                                    right: AppSpacing.sm,
                                  ),
                                  child: InputChip(
                                    key: ValueKey('active-filter-$key'),
                                    label: Text(label),
                                    visualDensity: VisualDensity.compact,
                                    deleteIcon: Icon(
                                      Icons.close,
                                      size: 16 * iconScale(context),
                                    ),
                                    onDeleted: () => _removeChip({key}),
                                    deleteButtonTooltipMessage: 'Remove',
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Never wider than half the screen; it shrinks with very large text.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width / 2,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: TextButton(
                key: const ValueKey('active-filter-clear-all'),
                onPressed: () =>
                    _removeChip({for (final (key, _, _) in chips) key}),
                child: const Text('Clear All'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
