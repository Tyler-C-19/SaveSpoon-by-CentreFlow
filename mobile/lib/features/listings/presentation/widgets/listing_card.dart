import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/listing.dart';
import 'listing_image.dart';

String pickupLabel(BuildContext context, Listing listing) =>
    pickupRangeLabel(context, listing.pickupStart, listing.pickupEnd);

String pickupRangeLabel(BuildContext context, DateTime start, DateTime end) {
  final localizations = MaterialLocalizations.of(context);
  String time(DateTime value) =>
      localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value));
  final now = DateTime.now();
  final isToday =
      start.year == now.year &&
      start.month == now.month &&
      start.day == now.day;
  final day = isToday ? 'Today' : localizations.formatShortMonthDay(start);
  return '$day, ${time(start)} - ${time(end)}';
}

class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    this.showBadges = false,
    this.onTap,
    this.relisted = false,
    this.onRelist,
  });

  static const double browseHeight = 250;

  final Listing listing;
  final bool showBadges;
  final VoidCallback? onTap;
  // Vendor cards only: relisted while the vendor has stayed on the tab.
  final bool relisted;
  // Vendor cards only: a Relist button on the picture once pickup has ended.
  final VoidCallback? onRelist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    final muted = small?.copyWith(color: AppColors.textMuted);
    final now = DateTime.now();
    final unlisted = listing.unlistedLabelAt(now);
    final badge = showBadges ? listing.badgeAt(now) : null;
    final showRelist =
        onRelist != null && !showBadges && listing.canRelistAt(now);
    final ribbons = unlisted == null
        ? null
        : Positioned(
            top: AppSpacing.sm,
            left: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Ribbon(
                  text: unlisted,
                  color: AppColors.endingSoon,
                  fill: AppColors.endingSoonPale,
                ),
                // Relisted while turned off: a second ribbon under the first.
                if (relisted) ...[
                  const SizedBox(height: AppSpacing.xs),
                  KeyedSubtree(
                    key: const ValueKey('relisted-ribbon'),
                    child: _Ribbon(
                      text: 'Relisted',
                      color: colors.primary,
                      fill: AppColors.page,
                    ),
                  ),
                ],
              ],
            ),
          );
    // With "Relist Now", the picture and text fade but its label doesn't;
    // otherwise the whole card fades.
    Widget faded(Widget child) =>
        showRelist ? Opacity(opacity: 0.7, child: child) : child;
    // With "Relist Now", the text area has its own tap and ripple.
    Widget textTap(Widget child) => showRelist && onTap != null
        ? Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('listing-card-${listing.id}'),
              onTap: onTap,
              child: child,
            ),
          )
        : child;

    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: unlisted == null ? AppShadows.card : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _withRelist(
              showRelist ? onRelist : null,
              onPhoto: listing.cardImageUrl != null,
              ribbons: ribbons,
              faded(
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: unlisted == null
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.primaryPale,
                              AppColors.primarySoft,
                            ],
                          )
                        : null,
                    color: unlisted == null ? null : AppColors.unlisted,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ListingImage(
                        url: listing.cardImageUrl,
                        category: listing.category,
                        greyed: unlisted != null,
                        greyColor: AppColors.unlisted,
                        showIcon: !showRelist,
                      ),
                      if (badge != null)
                        Positioned(
                          top: AppSpacing.sm,
                          left: 0,
                          child: ListingRibbon(badge: badge, listing: listing),
                        ),
                      if (unlisted == null && listing.isHalal == false)
                        Positioned(
                          top: AppSpacing.sm,
                          right: AppSpacing.sm,
                          child: _Pill(
                            text: 'Non-Halal',
                            color: colors.onSurface,
                          ),
                        ),
                      if (showBadges && unlisted == null)
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
          ),
          textTap(
            faded(
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (listing.stallName != null)
                      Text(
                        'From ${listing.stallName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    Text(
                      listing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // Shrinks rather than overflow a narrow card.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            moneyLabel(listing.discountedPrice),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: unlisted == null
                                  ? colors.primary
                                  : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            moneyLabel(listing.originalPrice),
                            maxLines: 1,
                            style: muted?.copyWith(
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _InfoLine(
                      icon: Icons.schedule,
                      text: pickupLabel(context, listing),
                    ),
                    if (!showBadges)
                      _InfoLine(
                        icon: Icons.inventory_2_outlined,
                        text: '${listing.quantityAvailable} in stock',
                      ),
                    _InfoLine(
                      icon: Icons.info_outline,
                      text: 'Allergens: ${listing.allergenSummary}',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final tapArea = onTap == null
        ? null
        : Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('listing-card-${listing.id}'),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: onTap,
            ),
          );

    if (unlisted == null) {
      if (tapArea == null && !relisted) return card;
      return Stack(
        fit: StackFit.expand,
        children: [
          card,
          if (relisted)
            Positioned(
              key: const ValueKey('relisted-ribbon'),
              top: AppSpacing.sm,
              left: 0,
              child: _Ribbon(
                text: 'Relisted',
                color: colors.primary,
                fill: AppColors.page,
              ),
            ),
          ?tapArea,
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showRelist) card else Opacity(opacity: 0.7, child: card),
        // With "Relist Now" the ribbons sit inside the picture, under it.
        if (!showRelist) ?ribbons,
        if (!showRelist) ?tapArea,
      ],
    );
  }
}

// The greyed picture shows "Relist Now"; tapping the picture relists. Over a
// photo, a dark shade with white words keeps it readable; without a photo
// the words stay green on the plain background.
Widget _withRelist(
  VoidCallback? onRelist,
  Widget picture, {
  bool onPhoto = false,
  Widget? ribbons,
}) {
  if (onRelist == null) return picture;
  return Stack(
    fit: StackFit.expand,
    children: [
      picture,
      if (onPhoto)
        Builder(
          builder: (context) => ColoredBox(
            key: const ValueKey('relist-now-shade'),
            color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.45),
          ),
        ),
      ?ribbons,
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('card-relist'),
          onTap: onRelist,
          child: Builder(
            builder: (context) {
              final theme = Theme.of(context);
              final color = onPhoto
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.primary;
              // Shrinks rather than overflow a small picture or large text.
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      key: const ValueKey('relist-now'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.replay, size: 32, color: color),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Relist Now',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
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
        children: [
          Icon(icon, size: 13, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class ListingRibbon extends StatelessWidget {
  const ListingRibbon({super.key, required this.badge, required this.listing});

  final ListingBadge badge;
  final Listing listing;

  @override
  Widget build(BuildContext context) {
    return switch (badge) {
      ListingBadge.lowStock => _Ribbon(
        text: listing.lowStockLabel,
        color: AppColors.lowStock,
        fill: AppColors.lowStockPale,
      ),
      ListingBadge.sellingFast => const _Ribbon(
        text: 'Selling Fast',
        color: AppColors.sellingFast,
        fill: AppColors.sellingFastPale,
      ),
      ListingBadge.endingSoon => const _Ribbon(
        text: 'Ending Soon',
        color: AppColors.endingSoon,
        fill: AppColors.endingSoonPale,
      ),
      ListingBadge.isNew => const _Ribbon(
        text: 'New',
        color: AppColors.primary,
        fill: AppColors.page,
      ),
    };
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.text, required this.color, required this.fill});

  final String text;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: color),
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(AppRadius.md),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class SavePill extends StatelessWidget {
  const SavePill({super.key, required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) =>
      _Pill(text: 'Save ${listing.savePercent}%', color: AppColors.onWarning);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
