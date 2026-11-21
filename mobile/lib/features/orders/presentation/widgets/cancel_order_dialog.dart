import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/order.dart';

class CancelChoice {
  const CancelChoice({this.reason, this.wholeCheckout = false});

  final CancelReason? reason;
  final bool wholeCheckout;
}

// One order, from Order Details or a single-item Order Placed page.
// Returns null when the customer keeps the order.
Future<CancelChoice?> showCancelOrderDialog(
  BuildContext context,
  Order order,
) => showDialog<CancelChoice>(
  context: context,
  builder: (context) => _CancelOrderDialog(orders: [order]),
);

// Every order from a checkout that was just placed.
Future<CancelChoice?> showCancelCheckoutDialog(
  BuildContext context,
  List<Order> orders,
) => showDialog<CancelChoice>(
  context: context,
  builder: (context) => _CancelOrderDialog(orders: orders),
);

class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog({required this.orders});

  final List<Order> orders;

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  CancelReason? _reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textMuted,
    );
    final orders = widget.orders;
    final several = orders.length > 1;
    final order = orders.first;
    final others = several ? const <CheckoutItem>[] : order.checkoutOrders;
    final otherCancellable = several ? 0 : order.otherCancellable;

    void close({required bool wholeCheckout}) => Navigator.pop(
      context,
      CancelChoice(reason: _reason, wholeCheckout: wholeCheckout),
    );

    return AlertDialog(
      title: Text(several ? 'Cancel these orders?' : 'Cancel this order?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final item in orders)
              _ItemLine('${item.quantity} x ${item.itemName}', item.stallName),
            const SizedBox(height: AppSpacing.xs),
            Text("This can't be undone.", style: muted),
            if (others.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                others.length == 1
                    ? 'This item was ordered together with 1 other item in '
                          'the same checkout:'
                    : 'This item was ordered together with ${others.length} '
                          'other items in the same checkout:',
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final other in others)
                _ItemLine(
                  '${other.quantity} x ${other.itemName}',
                  other.canCancel
                      ? other.stallName
                      : '${other.stallName}, can no longer be cancelled',
                ),
            ],
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<CancelReason>(
              key: const ValueKey('cancel-reason'),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Reason'),
              hint: const Text('Choose a reason (optional)'),
              items: [
                for (final reason in CancelReason.values)
                  DropdownMenuItem(value: reason, child: Text(reason.label)),
              ],
              onChanged: (reason) => setState(() => _reason = reason),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(several ? 'Keep Orders' : 'Keep Order'),
        ),
        if (several || otherCancellable > 0)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: error),
            onPressed: () => close(wholeCheckout: true),
            child: Text(
              'Cancel All ${several ? orders.length : otherCancellable + 1} '
              'Orders',
            ),
          ),
        if (!several)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: error),
            onPressed: () => close(wholeCheckout: false),
            child: Text(
              otherCancellable > 0 ? 'Cancel This Order Only' : 'Cancel Order',
            ),
          ),
      ],
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine(this.title, this.detail);

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: '  ($detail)',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}
