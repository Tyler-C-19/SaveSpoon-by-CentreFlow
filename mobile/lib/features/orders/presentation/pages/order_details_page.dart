import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/load_error.dart';
import '../../../listings/domain/listing.dart';
import '../../../listings/presentation/widgets/food_thumbnail.dart';
import '../../../listings/presentation/widgets/listing_card.dart';
import '../../data/order_repository.dart';
import '../../domain/order.dart';
import '../widgets/cancel_order_dialog.dart';
import '../widgets/order_card.dart';
import '../widgets/order_status_chip.dart';
import 'order_cancelled_page.dart';

class OrderDetailsPage extends StatefulWidget {
  const OrderDetailsPage({super.key, required this.orderId, this.initial});

  final String orderId;
  final Order? initial;

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  late Order? _order = widget.initial;
  String? _error;
  // The list's copy has no cancel time, so the button waits for this page's own load.
  bool _loaded = false;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await context.read<OrderRepository>().fetchOrder(
        widget.orderId,
      );
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_order == null) setState(() => _error = e.message);
    }
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  Future<void> _cancel(Order order) async {
    final choice = await showCancelOrderDialog(context, order);
    if (choice == null || !mounted) return;

    setState(() => _cancelling = true);
    try {
      final result = await context.read<OrderRepository>().cancelOrder(
        order.id,
        reason: choice.reason,
        wholeCheckout: choice.wholeCheckout,
      );
      if (!mounted) return;
      setState(() => _cancelling = false);
      _load();
      await Navigator.of(context).push(
        orderCancelledRoute(
          OrderCancelledPage(
            cancelled: result.cancelled,
            skipped: result.skipped,
            onDone: (context) => context.go(AppRoutes.customerOrders),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Order Details')),
      body: order != null
          ? _Details(
              order: order,
              cancel: _loaded && _CancelSection.showsFor(order, DateTime.now())
                  ? _CancelSection(
                      order: order,
                      busy: _cancelling,
                      onCancel: () => _cancel(order),
                    )
                  : null,
            )
          : Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: LoadError(message: error, onRetry: _retry),
                    ),
            ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.order, this.cancel});

  final Order order;
  final Widget? cancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final style = OrderStageStyle.of(context, order.stageAt(now));
    final unitPrice = order.unitPrice;
    final placed = order.createdAt;
    final cancelledAt = order.status == 'cancelled' ? order.cancelledAt : null;
    final address = order.pickupAddress;
    final cancelSection = cancel;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(child: FoodThumbnail(category: order.category, size: 160)),
        const SizedBox(height: AppSpacing.md),
        Text(
          order.itemName,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          order.stallName,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionCard(
          title: 'Pickup Details',
          trailing: Container(
            key: const ValueKey('order-status-banner'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: style.border == null
                  ? null
                  : Border.all(color: style.border!),
            ),
            child: Text(
              style.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: style.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          children: [
            if (address != null)
              _Field(
                icon: Icons.location_on_outlined,
                label: 'Address',
                value: address,
              ),
            _Field(
              icon: Icons.schedule,
              label: 'Pickup Time',
              value: pickupRangeLabel(
                context,
                order.pickupStart,
                order.pickupEnd,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _SectionCard(
          title: 'Order Summary',
          children: [
            _Field(
              icon: Icons.shopping_bag_outlined,
              label: 'Quantity',
              value: '${order.quantity}',
            ),
            if (unitPrice != null)
              _Field(
                icon: Icons.sell_outlined,
                label: 'Price Per Item',
                value: moneyLabel(unitPrice),
              ),
            _Field(
              icon: Icons.payments_outlined,
              label: 'Payment Method',
              value: payAtPickupLabel,
            ),
            if (placed != null)
              _Field(
                icon: Icons.event_outlined,
                label: 'Ordered',
                value: orderPlacedLabel(context, placed, now: now),
              ),
            if (cancelledAt != null)
              _Field(
                key: const ValueKey('order-cancelled-on'),
                icon: Icons.cancel_outlined,
                label: 'Cancelled On',
                value: orderPlacedLabel(context, cancelledAt, now: now),
              ),
            const Divider(height: AppSpacing.lg),
            _Field(
              icon: Icons.receipt_long_outlined,
              label: 'Total Price',
              value: moneyLabel(order.totalPrice),
              highlight: true,
            ),
          ],
        ),
        // Fades in once the page's own load says whether it can be cancelled.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: cancelSection == null
              ? const SizedBox.shrink()
              : Padding(
                  key: const ValueKey('cancel-section'),
                  padding: const EdgeInsets.only(top: AppSpacing.lg),
                  child: cancelSection,
                ),
        ),
      ],
    );
  }
}

class _CancelSection extends StatelessWidget {
  const _CancelSection({
    required this.order,
    required this.busy,
    required this.onCancel,
  });

  final Order order;
  final bool busy;
  final VoidCallback onCancel;

  // Only open orders whose pickup hasn't ended get this section.
  static bool showsFor(Order order, DateTime now) =>
      order.canCancelAt(now) || order.cancelClosedReason(now) != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final until = order.cancelUntil;
    final closed = order.cancelClosedReason(now);

    if (closed != null || until == null || !order.canCancelAt(now)) {
      return OrderNote(closed ?? '', key: const ValueKey('cancel-note'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderNote(
          'You can cancel this order until '
          '${cancelUntilLabel(context, until, now)}.',
          key: const ValueKey('cancel-note'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          key: const ValueKey('cancel-order-button'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.error,
            side: BorderSide(color: colors.error),
          ),
          onPressed: busy ? null : onCancel,
          child: busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Cancel Order'),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                Text(
                  value,
                  style: highlight
                      ? theme.textTheme.titleMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
                        )
                      : theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
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
