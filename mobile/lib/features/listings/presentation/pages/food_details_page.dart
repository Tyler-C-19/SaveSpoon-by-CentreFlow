import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/quantity_stepper.dart';
import '../../../orders/data/order_repository.dart';
import '../../../orders/domain/order.dart';
import '../../../orders/domain/request_id.dart';
import '../../../orders/presentation/widgets/confirm_order_dialog.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';
import '../widgets/category_picker.dart';
import '../widgets/listing_card.dart';

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
    try {
      final listing = await context.read<ListingRepository>().fetchDetails(
        widget.listingId,
      );
      if (!mounted) return;
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
      appBar: AppBar(title: Text(listing?.stallName ?? '')),
      body: listing != null
          ? _Details(listing: listing)
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
  const _Details({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final badge = listing.badgeAt(DateTime.now());
    final description = listing.description;
    final address = listing.pickupAddress;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(
            height: 200,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryPale, AppColors.primarySoft],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Icon(
                      categoryIcon(listing.category),
                      size: 80,
                      color: colors.primary,
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
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              if (address != null)
                _InfoRow(
                  icon: Icons.location_on_outlined,
                  label: 'Pickup address',
                  value: address,
                ),
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
