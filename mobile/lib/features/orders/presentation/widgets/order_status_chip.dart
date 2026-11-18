import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/order.dart';

class OrderStageStyle {
  const OrderStageStyle({
    required this.label,
    required this.background,
    required this.foreground,
    this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;

  static OrderStageStyle of(BuildContext context, OrderStage stage) {
    final colors = Theme.of(context).colorScheme;
    return switch (stage) {
      OrderStage.pending => const OrderStageStyle(
        label: 'Pending',
        background: AppColors.warningPale,
        foreground: AppColors.onWarning,
      ),
      OrderStage.confirmed => OrderStageStyle(
        label: 'Confirmed',
        background: colors.surface,
        foreground: colors.primary,
        border: colors.primary,
      ),
      OrderStage.completed => OrderStageStyle(
        label: 'Completed',
        background: colors.primary,
        foreground: colors.onPrimary,
      ),
      OrderStage.cancelled => const OrderStageStyle(
        label: 'Cancelled',
        background: AppColors.lowStockPale,
        foreground: AppColors.lowStock,
      ),
      OrderStage.pickupEnded => const OrderStageStyle(
        label: 'Pickup Ended',
        background: AppColors.unlisted,
        foreground: AppColors.textMuted,
      ),
    };
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.stage});

  final OrderStage stage;

  @override
  Widget build(BuildContext context) {
    final style = OrderStageStyle.of(context, stage);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: style.border == null ? null : Border.all(color: style.border!),
      ),
      child: Text(
        style.label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: style.foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}
