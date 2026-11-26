import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/auto_refresh.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../providers/favourites_provider.dart';
import '../providers/listing_changes.dart';
import 'quick_add_button.dart';
import 'running_out_strip.dart';

// Trial: "Your Favourites" on Home, up to 6 that are on sale now, with View All
// when there are more. Hidden when there are none. Loads by itself, so Home
// only places it.
class FavouritesStrip extends StatefulWidget {
  const FavouritesStrip({
    super.key,
    required this.heading,
    this.refreshWith,
    this.onOpen,
    this.onShowVendor,
    this.onPressDown,
    this.onSeeAll,
    this.onFirstLoad,
  });

  static const Duration animation = Duration(milliseconds: 250);

  final Widget heading;
  // Loads again whenever this changes, such as when Home reloads.
  final Object? refreshWith;
  final ValueChanged<Listing>? onOpen;
  final ValueChanged<Listing>? onShowVendor;
  final ValueChanged<Listing>? onPressDown;
  final VoidCallback? onSeeAll;
  // Called once the first load is back, whether or not it worked, so Home
  // can show everything together.
  final VoidCallback? onFirstLoad;

  @override
  State<FavouritesStrip> createState() => _FavouritesStripState();
}

class _FavouritesStripState extends State<FavouritesStrip> with AutoRefresh {
  static const Duration _settle = Duration(milliseconds: 400);

  late final FavouritesProvider _favourites;
  late final ListingChanges _changes;
  List<Listing> _listings = const [];
  bool _hasMore = false;
  // Nothing animates until the first load, so it shows at once like the
  // other sections on Home; later changes animate.
  bool _loaded = false;
  bool _reported = false;
  int _seenChanges = 0;
  int _requestId = 0;
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _favourites = context.read<FavouritesProvider>();
    _seenChanges = _favourites.changes;
    _favourites.addListener(_onFavouritesChanged);
    _changes = context.read<ListingChanges>();
    _changes.addListener(_load);
    _loadHearts();
    _load();
  }

  // Tries again on every refresh until the hearts have loaded.
  void _loadHearts() {
    final accountId = context.read<AuthProvider?>()?.user?.id;
    if (accountId != null) _favourites.ensureLoaded(accountId);
  }

  @override
  void didUpdateWidget(FavouritesStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Home's first load doesn't need a second one here.
    if (oldWidget.refreshWith != null &&
        !identical(oldWidget.refreshWith, widget.refreshWith)) {
      _load();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _favourites.removeListener(_onFavouritesChanged);
    _changes.removeListener(_load);
    super.dispose();
  }

  // A few quick heart taps load the strip once.
  void _onFavouritesChanged() {
    if (_favourites.changes == _seenChanges) return;
    _seenChanges = _favourites.changes;
    _wait?.cancel();
    _wait = Timer(_settle, _load);
  }

  @override
  Future<void> autoRefresh() {
    _loadHearts();
    return _load();
  }

  Future<void> _load() async {
    final request = ++_requestId;
    try {
      final found = await context.read<ListingRepository>().fetchFavourites();
      if (!mounted || request != _requestId) return;
      setState(() {
        _listings = found.listings;
        _hasMore = found.hasMore;
        _loaded = true;
      });
    } on ApiException {
      // Keeps what it showed; Home has its own error message.
    } finally {
      if (mounted && request == _requestId && !_reported) {
        _reported = true;
        widget.onFirstLoad?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final listings = [
      for (final item in _listings)
        if (item.isAvailableAt(now)) item,
    ];
    if (!_loaded) return const SizedBox.shrink();
    // Opens and closes smoothly, and cards fade in and out as hearts change.
    return AnimatedSize(
      duration: FavouritesStrip.animation,
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: FavouritesStrip.animation,
        child: listings.isEmpty
            ? const SizedBox(width: double.infinity)
            : Column(
                key: const ValueKey('favourites-strip'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      0,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(child: widget.heading),
                        if (_hasMore && widget.onSeeAll != null)
                          TextButton(
                            key: const ValueKey('favourites-view-all'),
                            onPressed: widget.onSeeAll,
                            child: const Text('View All'),
                          ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: FavouritesStrip.animation,
                    child: RunningOutStrip(
                      key: ValueKey(listings.map((item) => item.id).join()),
                      listings: listings,
                      onOpen: widget.onOpen,
                      onShowVendor: widget.onShowVendor,
                      onPressDown: widget.onPressDown,
                      actionsFor: (listing) => ListingActions(listing: listing),
                      actionsWidth: ListingActions.widthOf(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
      ),
    );
  }
}
