import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../listings/domain/listing.dart';

class OrderLine {
  const OrderLine({
    required this.itemName,
    required this.stallName,
    required this.quantity,
    required this.lineTotal,
    required this.pickup,
    this.pickupAddress,
  });

  final String itemName;
  final String stallName;
  final String? pickupAddress;
  final int quantity;
  final double lineTotal;
  final String pickup;
}

Future<bool> showConfirmOrderDialog(
  BuildContext context, {
  required List<OrderLine> lines,
  required double total,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmOrderDialog(lines: lines, total: total),
  );
  return confirmed ?? false;
}

class _ConfirmOrderDialog extends StatelessWidget {
  const _ConfirmOrderDialog({required this.lines, required this.total});

  final List<OrderLine> lines;
  final double total;

  Map<String, List<OrderLine>> get _byStall {
    final groups = <String, List<OrderLine>>{};
    for (final line in lines) {
      (groups[line.stallName] ??= []).add(line);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textMuted,
    );
    final totalStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Confirm your order', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final group in _byStall.entries) ...[
                      _StallHeader(
                        stallName: group.key,
                        address: group.value.first.pickupAddress,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (final line in group.value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${line.quantity} x ${line.itemName}',
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(moneyLabel(line.lineTotal)),
                                ],
                              ),
                              Text('Pickup: ${line.pickup}', style: muted),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Total', style: totalStyle)),
                Text(
                  moneyLabel(total),
                  key: const ValueKey('confirm-total'),
                  style: totalStyle?.copyWith(color: colors.primary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.payments_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text('Pay at pickup', style: muted),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Confirm'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StallHeader extends StatelessWidget {
  const _StallHeader({required this.stallName, required this.address});

  final String stallName;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final place = address;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, size: 18, color: colors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  stallName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (place != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 16,
                    color: colors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      place,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.primary,
                      ),
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
