import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/external_links.dart';
import '../../../../core/widgets/quantity_stepper.dart';
import '../../../orders/data/order_repository.dart';
import '../../../orders/domain/order.dart';
import '../../../orders/domain/request_id.dart';
import '../../../orders/presentation/widgets/confirm_order_dialog.dart';
import '../../../seller_profile/presentation/widgets/pickup_info_row.dart';
import '../../../seller_profile/domain/vendor_info.dart';
import '../../../seller_profile/presentation/widgets/vendor_details_card.dart';
import '../../../seller_profile/presentation/widgets/vendor_pane.dart';
import '../../../map/presentation/widgets/distance_pill.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../widgets/category_picker.dart';
import '../widgets/favourite_button.dart';
import '../widgets/listing_card.dart';
import '../widgets/listing_image.dart';
import 'photo_view_page.dart';

const String placeOrderFailed =
    "We couldn't place your order. Please try again.";
const String addToCartFailed =
    "We couldn't add this to your cart. Please try again.";

const Set<String> _leavingCodes = {'SOLD_OUT', 'PICKUP_ENDED', 'LISTING_GONE'};

class FoodDetailsPage extends StatefulWidget {
  const FoodDetailsPage({
    super.key,
    required this.listingId,
    required this.onAddToCart,
    required this.onOrdered,
  });

  final String listingId;
  final Future<String> Function(BuildContext context, String id, int quantity)
  onAddToCart;
  final void Function(BuildContext context, List<Order> orders) onOrdered;

  @override
  State<FoodDetailsPage> createState() => _FoodDetailsPageState();
}

class _FoodDetailsPageState extends State<FoodDetailsPage> {
  Listing? _listing;
  String? _error;
  int _quantity = 1;
  bool _ordering = false;
  bool _adding = false;
  String? _requestId;
  VendorInfo? _vendorInfo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _leave(String message) {
    if (mounted) Navigator.of(context).pop(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    final repository = context.read<ListingRepository>();
    try {
      final listing = await repository.fetchDetails(widget.listingId);
      if (!mounted) return;
      _loadVendor(repository, listing.id);
      final now = DateTime.now();
      if (!listing.isAvailableAt(now)) {
        _leave(listing.unavailableMessageAt(now));
        return;
      }
      setState(() {
        _listing = listing;
        _error = null;
        if (_quantity > listing.quantityAvailable) {
          _quantity = listing.quantityAvailable;
          _requestId = null;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_leavingCodes.contains(e.code)) {
        _leave(e.message);
      } else if (_listing == null) {
        setState(() => _error = e.message);
      } else {
        _showMessage(e.message);
      }
    }
  }

  Future<void> _handleFailure(ApiException e, String fallback) async {
    if (_leavingCodes.contains(e.code)) {
      _leave(e.message);
      return;
    }
    final status = e.statusCode;
    if (status == null || status >= 500) {
      _showMessage(fallback);
      return;
    }
    _requestId = null;
    _showMessage(e.message);
    if (e.code == 'NOT_ENOUGH_STOCK') await _load();
  }

  Future<void> _orderNow(Listing listing) async {
    final confirmed = await showConfirmOrderDialog(
      context,
      lines: [
        OrderLine(
          itemName: listing.title,
          stallName: listing.stallName ?? '',
          pickupAddress: listing.pickupAddress,
          quantity: _quantity,
          lineTotal: _quantity * listing.discountedPrice,
          pickup: pickupLabel(context, listing),
        ),
      ],
      total: _quantity * listing.discountedPrice,
    );
    if (!confirmed || !mounted) return;

    setState(() => _ordering = true);
    final requestId = _requestId ??= newRequestId();
    try {
      final order = await context.read<OrderRepository>().place(
        listingId: listing.id,
        quantity: _quantity,
        requestId: requestId,
      );
      if (mounted) widget.onOrdered(context, [order]);
    } on ApiException catch (e) {
      if (mounted) await _handleFailure(e, placeOrderFailed);
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  Future<void> _addToCart(Listing listing) async {
    setState(() => _adding = true);
    try {
      final message = await widget.onAddToCart(context, listing.id, _quantity);
      if (mounted) _showMessage(message);
    } on ApiException catch (e) {
      if (mounted) await _handleFailure(e, addToCartFailed);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Details'),
        actions: [
          if (listing != null)
            FavouriteButton(
              listingId: listing.id,
              size: 48,
              maxSize: kToolbarHeight,
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: listing != null
          ? _Details(
              listing: listing,
              vendorInfo: _vendorInfo,
              onShowVendor: () => showVendorPane(context, listing: listing),
            )
          : _error == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _load();
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: listing == null ? null : _orderBar(listing),
    );
  }

  // Loaded alongside the food so the vendor pane usually opens already filled.
  void _loadVendor(ListingRepository repository, String id) {
    _vendorInfo ??= repository.cachedVendorInfo(id);
    if (repository.isVendorInfoFresh(id)) return;
    repository.fetchVendorInfo(id).then((info) {
      if (mounted) setState(() => _vendorInfo = info);
    }, onError: (_) {});
  }

  Widget _orderBar(Listing listing) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = _ordering || _adding;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.page,
        boxShadow: AppShadows.card,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  QuantityStepper(
                    value: _quantity,
                    max: listing.quantityAvailable,
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            _quantity = value;
                            _requestId = null;
                          }),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        moneyLabel(_quantity * listing.discountedPrice),
                        key: const ValueKey('details-total'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(color: colors.primary, width: 1.5),
                      ),
                      onPressed: busy ? null : () => _addToCart(listing),
                      icon: _adding
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.shopping_cart_outlined, size: 20),
                      label: const Text('Add to Cart'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => _orderNow(listing),
                      icon: _ordering
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt, size: 20),
                      label: const Text('Order Now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.listing,
    required this.onShowVendor,
    this.vendorInfo,
  });

  final Listing listing;
  final VendorInfo? vendorInfo;
  final VoidCallback onShowVendor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final badge = listing.badgeAt(DateTime.now());
    final description = listing.description;
    final address = listing.pickupAddress;
    final location = listing.pickupLocation;
    final phone = listing.vendorPhone;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(
            height: 200,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ListingImage(
                  url: listing.imageUrl,
                  placeholderUrl: listing.imageThumbUrl,
                  category: listing.category,
                  iconSize: 80,
                ),
                if (listing.imageUrl case final url?)
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      key: const ValueKey('open-photo'),
                      onTap: () => openPhotoView(context, url, listing.title),
                    ),
                  ),
                if (badge != null)
                  Positioned(
                    top: AppSpacing.md,
                    left: 0,
                    child: ListingRibbon(badge: badge, listing: listing),
                  ),
                Positioned(
                  bottom: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: SavePill(listing: listing),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          listing.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              moneyLabel(listing.discountedPrice),
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              moneyLabel(listing.originalPrice),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ],
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(description),
        ],
        const SizedBox(height: AppSpacing.md),
        VendorDetailsCard(
          stallName: listing.stallName ?? '',
          info: vendorInfo,
          onTap: onShowVendor,
          details: [
            if (address != null)
              PickupInfoRow(
                icon: Icons.location_on_outlined,
                label: 'Pickup address',
                value: address,
                note: DistanceLine(pin: location),
                actionLabel: directionsLabel,
                actionIcon: directionsIcon,
                actionKey: const ValueKey('details-find-on-maps'),
                onAction: location == null
                    ? null
                    : () => openDirections(
                        lat: location.lat,
                        lng: location.lng,
                        placeId: listing.pickupPlaceId,
                        address: address,
                        context: context,
                      ),
              ),
            if (phone != null)
              PickupInfoRow(
                icon: Icons.phone_outlined,
                label: 'Contact',
                value: phone,
                actionLabel: 'Call',
                actionIcon: Icons.call_outlined,
                actionKey: const ValueKey('details-call'),
                onAction: () => callPhone(phone, context: context),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              _InfoRow(
                icon: Icons.schedule,
                label: 'Pickup time',
                value: pickupLabel(context, listing),
              ),
              _InfoRow(
                icon: Icons.inventory_2_outlined,
                label: 'Stock',
                value: '${listing.quantityAvailable} left',
                valueColor: listing.isLowStock ? AppColors.lowStock : null,
              ),
              _InfoRow(
                icon: categoryIcon(listing.category),
                label: 'Category',
                value: listing.category ?? 'Other',
              ),
              _InfoRow(
                icon: Icons.verified_outlined,
                label: 'Halal',
                value: listing.isHalal == true ? 'Yes' : 'No',
              ),
              _InfoRow(
                icon: Icons.info_outline,
                label: 'Allergens',
                value: listing.allergenSummary,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w600,
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
