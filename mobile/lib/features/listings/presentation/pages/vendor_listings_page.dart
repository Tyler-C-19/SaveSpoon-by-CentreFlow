import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/auto_refresh.dart';
import '../../../../core/widgets/load_error.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../widgets/add_listing_button.dart';
import '../widgets/listing_card.dart';

enum ListingSort { newest, lowStock, pricing, popularity }

extension on ListingSort {
  String get label => switch (this) {
    ListingSort.newest => 'Newest',
    ListingSort.lowStock => 'Low Stock',
    ListingSort.pricing => 'Pricing',
    ListingSort.popularity => 'Popularity',
  };
}

// Newest first is how the server sends them; the others keep that order on ties.
List<Listing> sortListings(List<Listing> listings, ListingSort sort) {
  final int Function(Listing a, Listing b)? compare = switch (sort) {
    ListingSort.newest => null,
    ListingSort.lowStock => (a, b) => a.quantityAvailable.compareTo(
      b.quantityAvailable,
    ),
    ListingSort.pricing => (a, b) => a.discountedPrice.compareTo(
      b.discountedPrice,
    ),
    ListingSort.popularity => (a, b) => b.soldCount.compareTo(a.soldCount),
  };
  if (compare == null) return [...listings];
  final indexed = listings.indexed.toList()
    ..sort((a, b) {
      final result = compare(a.$2, b.$2);
      return result != 0 ? result : a.$1.compareTo(b.$1);
    });
  return [for (final (_, listing) in indexed) listing];
}

// Listed means customers can see and order it now; everything else is unlisted.
// Just-relisted items first, then listed, then unlisted; the chosen sort
// still orders items within each group.
List<Listing> prioritiseListings(
  List<Listing> listings,
  Set<String> relistedIds,
  DateTime now,
) => [
  for (final item in listings)
    if (relistedIds.contains(item.id)) item,
  for (final item in listings)
    if (!relistedIds.contains(item.id) && item.isAvailableAt(now)) item,
  for (final item in listings)
    if (!relistedIds.contains(item.id) && !item.isAvailableAt(now)) item,
];

List<Listing> filterListings(
  List<Listing> listings,
  bool? listedOnly,
  DateTime now,
) => listedOnly == null
    ? listings
    : [
        for (final item in listings)
          if (item.isAvailableAt(now) == listedOnly) item,
      ];

class VendorListingsPage extends StatefulWidget {
  const VendorListingsPage({super.key});

  @override
  State<VendorListingsPage> createState() => _VendorListingsPageState();
}

class _VendorListingsPageState extends State<VendorListingsPage>
    with AutoRefresh {
  static const double _cardHeight = 250;

  List<Listing>? _listings;
  String? _error;
  ListingSort _sort = ListingSort.newest;
  // Null shows all; true only listed; false only unlisted.
  bool? _listedOnly;
  final Set<String> _relistedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> autoRefresh() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _listings = null;
        _error = null;
      });
    }
    try {
      final listings = await context.read<ListingRepository>().fetchMine();
      if (mounted) {
        setState(() {
          _listings = listings;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_listings == null) {
        setState(() => _error = e.message);
      } else if (!silent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Widget _scrollable(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );

  Future<void> _addListing() async {
    final mine = _listings ?? const <Listing>[];
    final result = await context.push<Listing>(
      AppRoutes.vendorAddListing,
      extra: mine,
    );
    if (result == null || !mounted) return;
    // A listing the vendor already had was relisted from the same-name popup.
    if (mine.any((item) => item.id == result.id)) {
      _relisted(result);
      return;
    }
    setState(() => _listings = [result, ...mine]);
  }

  Future<void> _relistListing(Listing listing) async {
    final relisted = await context.push<Listing>(
      AppRoutes.vendorRelistFor(listing.id),
      extra: listing,
    );
    if (relisted != null && mounted) _relisted(relisted);
  }

  void _relisted(Listing listing) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${listing.title} is back on sale.')),
      );
    _relistedIds.add(listing.id);
    _load(silent: true);
  }

  Future<void> _openListing(Listing listing) async {
    await context.push<void>(
      AppRoutes.vendorListingFor(listing.id),
      extra: listing,
    );
    if (!mounted) return;
    await _load(silent: true);
    // A newer listedAt means it was relisted from its own page.
    final latest = _listings
        ?.where((item) => item.id == listing.id)
        .firstOrNull;
    final before = listing.listedAt;
    final after = latest?.listedAt;
    if (before != null && after != null && after.isAfter(before) && mounted) {
      setState(() => _relistedIds.add(listing.id));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The ribbon lasts only while the vendor stays on this tab.
    if (!TickerMode.valuesOf(context).enabled) _relistedIds.clear();
  }

  // One labelled, sideways-scrolling row of single-choice chips.
  Widget _chipRow<T>(
    String label,
    List<(String, T)> options,
    T selected,
    ValueChanged<T> onChanged,
  ) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: AppColors.textMuted),
          ),
        ),
        for (final (text, value) in options)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: Text(text),
              selected: selected == value,
              onSelected: (_) => setState(() => onChanged(value)),
            ),
          ),
      ],
    ),
  );

  Widget _chips() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _chipRow<bool?>(
        'Show:',
        const [('All', null), ('Listed', true), ('Unlisted', false)],
        _listedOnly,
        (value) => _listedOnly = value,
      ),
      _chipRow<ListingSort>(
        'Sort by:',
        [for (final sort in ListingSort.values) (sort.label, sort)],
        _sort,
        (value) => _sort = value,
      ),
    ],
  );

  Widget _body(BuildContext context) {
    if (_error != null) {
      return _scrollable(LoadError(message: _error!, onRetry: _load));
    }
    final loaded = _listings;
    if (loaded == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loaded.isEmpty) {
      return _scrollable(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fastfood_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No listings yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text('Add your surplus food so customers can find it.'),
          ],
        ),
      );
    }
    final now = DateTime.now();
    final listings = prioritiseListings(
      sortListings(filterListings(loaded, _listedOnly, now), _sort),
      _relistedIds,
      now,
    );
    if (listings.isEmpty) {
      return _scrollable(
        Text(
          _listedOnly == true
              ? 'Nothing is listed right now.'
              : 'Nothing is unlisted right now.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.textMuted),
        ),
      );
    }
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: _cardHeight,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
      ),
      itemCount: listings.length,
      itemBuilder: (context, index) => ListingCard(
        listing: listings[index],
        onTap: () => _openListing(listings[index]),
        relisted: _relistedIds.contains(listings[index].id),
        onRelist: () => _relistListing(listings[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'All Listings',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                AddListingButton(onPressed: _addListing),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_listings?.isNotEmpty ?? false) ...[
              _chips(),
              const SizedBox(height: AppSpacing.sm),
            ],
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(silent: true),
                child: _body(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
