import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/quantity_stepper.dart';
import '../../../listings/domain/listing.dart';
import '../../../listings/presentation/widgets/food_thumbnail.dart';
import '../../../listings/presentation/widgets/listing_card.dart';
import '../../domain/cart.dart';

class CartItemTile extends StatelessWidget {
  const CartItemTile({
    super.key,
    required this.item,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  static const double thumbnailSize = 72;

  final CartItem item;
  final ValueChanged<int>? onQuantityChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final start = item.pickupStart;
    final end = item.pickupEnd;
    final reason = item.reason;
    final address = item.pickupAddress;

    final tile = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: item.available ? colors.surface : AppColors.unlisted,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodThumbnail(
                category: item.category,
                size: thumbnailSize,
                available: item.available,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.itemName,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove ${item.itemName}',
                          visualDensity: VisualDensity.compact,
                          color: colors.error,
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: onRemove,
                        ),
                      ],
                    ),
                    if (reason != null)
                      Text(
                        reason,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.lowStock,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (address != null)
                      _InfoLine(
                        icon: Icons.location_on_outlined,
                        text: address,
                      ),
                    if (start != null && end != null)
                      _InfoLine(
                        icon: Icons.schedule,
                        text: pickupRangeLabel(context, start, end),
                      ),
                  ],
                ),
              ),
            ],
          ),
          for (final notice in item.notices)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                notice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.onWarning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (item.available) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                QuantityStepper(
                  value: item.quantity,
                  max: item.stockLeft ?? item.quantity,
                  onChanged: onQuantityChanged,
                ),
                const Spacer(),
                Text(
                  moneyLabel(item.lineTotal),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return item.available ? tile : Opacity(opacity: 0.7, child: tile);
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
