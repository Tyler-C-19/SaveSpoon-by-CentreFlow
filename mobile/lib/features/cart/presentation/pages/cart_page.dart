import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../listings/domain/listing.dart';
import '../../../listings/presentation/widgets/listing_card.dart';
import '../../../orders/domain/order.dart';
import '../../../orders/domain/request_id.dart';
import '../../../orders/presentation/widgets/confirm_order_dialog.dart';
import '../../domain/cart.dart';
import '../providers/cart_provider.dart';
import '../widgets/cart_item_tile.dart';

const String _placeFailed = "We couldn't place your order. Please try again.";

class CartPage extends StatefulWidget {
  const CartPage({super.key, required this.onOrdered});

  final void Function(BuildContext context, List<Order> orders) onOrdered;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  bool _busy = false;
  bool _placing = false;
  String? _requestId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CartProvider>().refresh();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _change(Future<void> Function(CartProvider cart) action) async {
    setState(() => _busy = true);
    _requestId = null;
    try {
      await action(context.read<CartProvider>());
    } on ApiException catch (e) {
      if (mounted) _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear your cart?'),
        content: const Text('This removes every item from your cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep items'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _change((cart) => cart.clearItems());
    }
  }

  Future<void> _removeItem(CartItem item) async {
    if (item.available) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove this item?'),
          content: Text('${item.itemName} will be removed from your cart.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep item'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _change((cart) => cart.remove(item.listingId));
  }

  Future<void> _placeOrder(Cart cart) async {
    final available = cart.availableItems;
    final confirmed = await showConfirmOrderDialog(
      context,
      lines: [
        for (final item in available)
          OrderLine(
            itemName: item.itemName,
            stallName: item.stallName,
            pickupAddress: item.pickupAddress,
            quantity: item.quantity,
            lineTotal: item.lineTotal,
            pickup: pickupRangeLabel(
              context,
              item.pickupStart!,
              item.pickupEnd!,
            ),
          ),
      ],
      total: cart.total,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _placing = true;
    });
    final provider = context.read<CartProvider>();
    final requestId = _requestId ??= newRequestId();
    try {
      final orders = await provider.checkout(
        requestId: requestId,
        expectedTotal: cart.total,
      );
      _requestId = null;
      await provider.refresh();
      if (mounted) widget.onOrdered(context, orders);
    } on ApiException catch (e) {
      if (!mounted) return;
      final status = e.statusCode;
      if (status == null || status >= 500) {
        _showMessage(_placeFailed);
      } else {
        _requestId = null;
        _showMessage(e.message);
        await provider.refresh();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _placing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CartProvider>();
    final cart = provider.cart;
    final error = provider.error;

    return SafeArea(
      child: cart != null
          ? RefreshIndicator(onRefresh: provider.refresh, child: _content(cart))
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: provider.refresh,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _content(Cart cart) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final title = Text(
      'My Cart',
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    );

    if (cart.items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          title,
          const SizedBox(height: 96),
          Icon(Icons.shopping_cart_outlined, size: 56, color: colors.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your cart is empty',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Add food from Home to order it here.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            Expanded(child: title),
            TextButton(
              onPressed: _busy ? null : _confirmClear,
              child: const Text('Clear Cart'),
            ),
          ],
        ),
        Text(
          "Items aren't held until you place your order.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (final warning in cart.warnings) _Warning(text: warning),
        for (final group in cart.itemsByStall.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text('From ${group.key}', style: theme.textTheme.titleSmall),
          ),
          for (final item in group.value)
            CartItemTile(
              item: item,
              onQuantityChanged: _busy
                  ? null
                  : (value) => _change(
                      (cart) => cart.setQuantity(item.listingId, value),
                    ),
              onRemove: _busy ? null : () => _removeItem(item),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (cart.hasUnavailable)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _change((cart) => cart.removeUnavailable()),
              child: const Text('Remove unavailable items'),
            ),
          ),
        Row(
          children: [
            Expanded(child: Text('Total', style: theme.textTheme.titleMedium)),
            Text(
              moneyLabel(cart.total),
              key: const ValueKey('cart-total'),
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Place Order',
          isLoading: _placing,
          onPressed: _busy || cart.availableItems.isEmpty
              ? null
              : () => _placeOrder(cart),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warningPale,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.onWarning,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.onWarning),
            ),
          ),
        ],
      ),
    );
  }
}
