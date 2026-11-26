import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/external_links.dart';
import '../../../listings/data/listing_repository.dart';
import '../../../listings/domain/listing.dart';
import '../../../listings/presentation/widgets/listing_card.dart';
import '../../../profile/presentation/widgets/profile_avatar.dart';
import '../../domain/vendor_info.dart';
import 'pickup_info_row.dart';
import '../../../map/presentation/widgets/distance_pill.dart';

const String vendorGone = 'This stall is no longer available.';
const String vendorLoadFailed = "Unable to load this stall's information.";
const String vendorLoadHint = 'Check your connection and try again.';

typedef OpenListing = Future<void> Function(Listing listing);

// Opens the stall's details as a sheet above the page and the tab bar. What
// [listing] already knows shows at once; the rest fills in when it arrives.
// Another listing opens on top of the sheet, so Back returns to it.
// [allItems] lists [listing] among the stall's items too (from the map), with
// [first] (what matched the map's search) ahead of the rest.
Future<void> showVendorPane(
  BuildContext context, {
  required Listing listing,
  OpenListing? onOpenListing,
  bool allItems = false,
  List<Listing> first = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => VendorPane(
      listing: listing,
      onOpenListing: onOpenListing ?? (other) => _openDetails(context, other),
      allItems: allItems,
      first: first,
    ),
  );
}

Future<void> _openDetails(BuildContext context, Listing listing) async {
  final message = await context.push<String>(
    AppRoutes.foodDetailsFor(listing.id),
  );
  if (!context.mounted || message == null) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class VendorPane extends StatefulWidget {
  const VendorPane({
    super.key,
    required this.listing,
    required this.onOpenListing,
    this.allItems = false,
    this.first = const [],
  });

  final Listing listing;
  final OpenListing onOpenListing;
  final bool allItems;
  final List<Listing> first;

  @override
  State<VendorPane> createState() => _VendorPaneState();
}

class _VendorPaneState extends State<VendorPane> {
  late final ListingRepository _repository;
  VendorInfo? _info;
  bool _loading = false;
  String? _error;
  bool _gone = false;
  String? _linkError;

  String get _listingId => widget.listing.id;

  @override
  void initState() {
    super.initState();
    _repository = context.read<ListingRepository>();
    _info = _repository.cachedVendorInfo(_listingId, all: widget.allItems);
    if (!_repository.isVendorInfoFresh(_listingId, all: widget.allItems)) {
      _loading = true;
      _fetch();
    }
  }

  void _load() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final info = await _repository.fetchVendorInfo(
        _listingId,
        all: widget.allItems,
      );
      if (mounted) setState(() => _info = info);
    } on ApiException catch (e) {
      if (!mounted) return;
      final gone = e.statusCode == 404;
      setState(() {
        _gone = gone;
        // An older copy stays on screen if refreshing it fails.
        if (gone || _info == null) {
          _error = gone ? vendorGone : vendorLoadFailed;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const int _stripSize = 4;

  // Search matches first, then the stall's other items, still up to 4.
  List<Listing> _firstItems(List<Listing> items) {
    if (widget.first.isEmpty) return items;
    final firstIds = {for (final item in widget.first) item.id};
    return [
      ...widget.first,
      for (final item in items)
        if (!firstIds.contains(item.id)) item,
    ].take(_stripSize).toList();
  }

  Future<void> _openLink(Future<bool> Function() open, String failed) async {
    setState(() => _linkError = null);
    final opened = await open();
    if (!opened && mounted) setState(() => _linkError = failed);
  }

  Future<void> _openListing(Listing listing) async {
    await widget.onOpenListing(listing);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        key: const ValueKey('vendor-pane'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _content(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final theme = Theme.of(context);
    final listing = widget.listing;
    final info = _gone ? null : _info;
    final name = info?.stallName ?? listing.stallName ?? '';
    final address = info?.address ?? listing.pickupAddress;
    final phone = info?.phone ?? listing.vendorPhone;
    final location = info?.location ?? listing.pickupLocation;
    final placeId = info?.placeId ?? listing.pickupPlaceId;
    final description = info?.description;
    final others = _firstItems(info?.otherListings ?? const <Listing>[]);
    final error = _error;
    final linkError = _linkError;

    final rows = [
      if (address != null && !_gone)
        PickupInfoRow(
          icon: Icons.location_on_outlined,
          label: 'Pickup address',
          value: address,
          note: DistanceLine(pin: location),
          actionLabel: directionsLabel,
          actionIcon: directionsIcon,
          actionKey: const ValueKey('pane-find-on-maps'),
          onAction: location == null
              ? null
              : () => _openLink(
                  () => openDirections(
                    lat: location.lat,
                    lng: location.lng,
                    placeId: placeId,
                    address: address,
                  ),
                  mapsFailed,
                ),
        ),
      if (phone != null && !_gone)
        PickupInfoRow(
          icon: Icons.phone_outlined,
          label: 'Contact',
          value: phone,
          actionLabel: 'Call',
          actionIcon: Icons.call_outlined,
          actionKey: const ValueKey('pane-call'),
          onAction: () => _openLink(() => callPhone(phone), phoneFailed),
        ),
    ];

    return [
      const _PaneHeading(
        icon: Icons.storefront,
        text: 'Vendor Details',
        large: true,
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          ProfileAvatar(
            name: name,
            photoUrl: info?.photoUrl,
            size: 64,
            isLoading: info == null && error == null,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      if (description != null && description.isNotEmpty)
        _FadeIn(
          key: const ValueKey('about'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.lg),
              const _PaneHeading(
                icon: Icons.info_outline,
                text: 'About This Stall',
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Text(description),
              ),
            ],
          ),
        ),
      if (rows.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(children: rows),
        ),
      ],
      if (linkError != null) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          linkError,
          key: const ValueKey('pane-link-error'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
      if (error != null)
        _FadeIn(
          key: ValueKey('error-$error'),
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: Column(
              children: [
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!_gone) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    vendorLoadHint,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if (!_gone)
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: const Text('Try Again'),
                  ),
              ],
            ),
          ),
        )
      else if (info == null)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (others.isNotEmpty)
        _FadeIn(
          key: const ValueKey('more'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.lg),
              _PaneHeading(
                icon: Icons.restaurant_menu,
                text: widget.allItems
                    ? 'On Sale at This Stall'
                    : 'More From This Stall',
              ),
              const SizedBox(height: AppSpacing.sm),
              // The Running Out Soon card and size, without the stall line.
              LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  key: const ValueKey('more-from-stall'),
                  height: ListingCard.browseHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: others.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (context, index) => SizedBox(
                      width: (constraints.maxWidth - AppSpacing.sm) / 2,
                      child: ListingCard(
                        listing: others[index],
                        showBadges: true,
                        inStallPane: true,
                        onTap: () => _openListing(others[index]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

// Same look as the Home section titles; [large] for the pane's own title.
class _PaneHeading extends StatelessWidget {
  const _PaneHeading({
    required this.icon,
    required this.text,
    this.large = false,
  });

  final IconData icon;
  final String text;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: large ? 24 : 22, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style:
                (large
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.titleMedium)
                    ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _FadeIn extends StatelessWidget {
  const _FadeIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}
