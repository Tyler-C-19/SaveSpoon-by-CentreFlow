import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../listings/domain/listing.dart';
import '../../../listings/presentation/widgets/food_thumbnail.dart';
import '../../../listings/presentation/widgets/listing_card.dart';
import '../../domain/order.dart';
import 'order_status_chip.dart';

const String payAtPickupLabel = 'Pay at Pickup';

// "Today, 3:45 PM", "Yesterday, ..." or "Tomorrow, ...", otherwise the date.
String orderPlacedLabel(
  BuildContext context,
  DateTime placed, {
  DateTime? now,
}) {
  final localizations = MaterialLocalizations.of(context);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(placed));
  final day = dateBucketLabel(placed, now ?? DateTime.now());
  final named = const {'Today', 'Yesterday', 'Tomorrow'}.contains(day);
  return '${named ? day : localizations.formatShortMonthDay(placed)}, $time';
}

// "5:30 PM" when it's today, else "tomorrow, 5:30 PM" or the date.
String cancelUntilLabel(BuildContext context, DateTime until, DateTime now) {
  final sameDay =
      until.year == now.year &&
      until.month == now.month &&
      until.day == now.day;
  return sameDay
      ? MaterialLocalizations.of(context)
            .formatTimeOfDay(TimeOfDay.fromDateTime(until))
      : orderPlacedLabel(
          context,
          until,
          now: now,
        ).replaceFirst('Tomorrow', 'tomorrow');
}

// A small muted note with an info icon, as used across the app.
class OrderNote extends StatelessWidget {
  const OrderNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

// Just the time, for a card under a header that already names its day.
String orderPlacedTimeLabel(BuildContext context, DateTime placed) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(placed));

// Buckets that collapse behind a summary card instead of listing every
// order, so a long history doesn't crowd the screen.
const Set<String> collapsibleDateBuckets = {'Older', 'Later'};

// Today / Yesterday / Tomorrow / This Week / Older / Later, relative to
// now. Covers both a past date (History, All) and a future one (Upcoming).
String dateBucketLabel(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  if (diff > 0) return diff <= 6 ? 'This Week' : 'Later';
  return diff >= -6 ? 'This Week' : 'Older';
}

class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.now,
    required this.onInfo,
    this.showPlacedDate = false,
  });

  final Order order;
  final DateTime now;
  final VoidCallback onInfo;
  final bool showPlacedDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textMuted,
    );
    final placed = order.createdAt;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onInfo,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FoodThumbnail(
                      category: order.category,
                      imageUrl: order.imageThumbUrl,
                      size: 72,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  order.itemName,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              if (placed != null) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  showPlacedDate
                                      ? orderPlacedLabel(
                                          context,
                                          placed,
                                          now: now,
                                        )
                                      : orderPlacedTimeLabel(context, placed),
                                  style: muted,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          OrderLine(
                            icon: Icons.storefront_outlined,
                            text: order.stallName,
                          ),
                          OrderLine(
                            icon: Icons.shopping_bag_outlined,
                            text: 'Quantity: ${order.quantity}',
                          ),
                          OrderLine(
                            icon: Icons.schedule,
                            text: pickupRangeLabel(
                              context,
                              order.pickupStart,
                              order.pickupEnd,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    OrderStatusChip(stage: order.stageAt(now)),
                    const Spacer(),
                    Text('Total', style: muted),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      moneyLabel(order.totalPrice),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// A header shown above the first of a run of orders from the same date
// bucket (Today, Yesterday, This Week, ...).
class OrderDateHeader extends StatelessWidget {
  const OrderDateHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textMuted),
      ),
    );
  }
}

// A single row standing in for a whole Older/Later bucket, so a long
// history doesn't load the screen with cards up front. Tapping expands it
// into the full cards in place.
class OrderGroupSummary extends StatelessWidget {
  const OrderGroupSummary({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm + AppSpacing.xs,
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 20, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    count == 1 ? '1 order' : '$count orders',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 20, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OrderLine extends StatelessWidget {
  const OrderLine({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
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
