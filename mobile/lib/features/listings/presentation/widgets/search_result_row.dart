import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/listing.dart';
import '../../../map/presentation/widgets/distance_pill.dart';
import 'favourite_button.dart';
import 'icon_scale.dart';
import 'listing_card.dart';
import 'listing_image.dart';

class SearchResultRow extends StatelessWidget {
  const SearchResultRow({
    super.key,
    required this.listing,
    this.onTap,
    this.onShowVendor,
    this.onPressDown,
    this.actions,
  });

  // The photo is up to this wide, and never more than 40% of the row.
  static const double thumbnailSize = 140;
  static const double thumbnailShare = 0.4;

  // Every row is this tall, so a short name or missing address leaves space.
  static const double contentHeight = 140;

  final Listing listing;
  final VoidCallback? onTap;
  // A long-press shows the stall.
  final VoidCallback? onShowVendor;
  // A finger touching the row, before it's a tap.
  final VoidCallback? onPressDown;
  // Buttons at the bottom right, such as the heart.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textMuted,
    );

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('search-result-${listing.id}'),
        onTap: onTap,
        onLongPress: onShowVendor,
        onTapDown: onPressDown == null ? null : (_) => onPressDown!(),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.outlineVariant),
          ),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: SizedBox(
            height:
                _textGrowth(context) * contentHeight +
                (_actionsBelow(context)
                    ? ListingIconButton.compactSize * iconScale(context)
                    : 0),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Thumbnail(
                    listing: listing,
                    width: constraints.maxWidth * thumbnailShare < thumbnailSize
                        ? constraints.maxWidth * thumbnailShare
                        : thumbnailSize,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      key: const ValueKey('search-result-text'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (listing.stallName != null)
                          Text(
                            'From ${listing.stallName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        _NameLine(listing: listing),
                        const SizedBox(height: AppSpacing.xs),
                        // Shrinks only when a narrow screen can't fit the line.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Text(
                                moneyLabel(listing.discountedPrice),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.primary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                moneyLabel(listing.originalPrice),
                                style: muted?.copyWith(
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              _Pill(
                                text: 'Save ${listing.savePercent}%',
                                color: AppColors.onWarning,
                                fill: AppColors.warningPale,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        _besideActions(
                          context,
                          _InfoLine(
                            icon: Icons.schedule,
                            text: pickupLabel(context, listing),
                          ),
                          listing.pickupAddress == null
                              ? null
                              : _InfoLine(
                                  icon: Icons.place_outlined,
                                  text: listing.pickupAddress!,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // With very large text the buttons go under the lines instead of beside
  // them, and the row grows to fit.
  bool _actionsBelow(BuildContext context) =>
      actions != null && iconScale(context) > 1.5;

  // The pickup and address lines, with the buttons at the bottom right.
  Widget _besideActions(BuildContext context, Widget pickup, Widget? address) {
    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [pickup, ?address],
    );
    if (actions == null) return lines;
    if (_actionsBelow(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          lines,
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: lines),
        const SizedBox(width: AppSpacing.xs),
        actions!,
      ],
    );
  }

  // Android grows small text far more than a large size like the row height,
  // so the row grows by as much as its smallest text does.
  static double _textGrowth(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(_smallestText) / _smallestText;
  static const double _smallestText = 12;
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.listing, required this.width});

  final Listing listing;
  final double width;

  @override
  Widget build(BuildContext context) {
    final badge = listing.badgeAt(DateTime.now());
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: width,
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
            ListingImage(
              url: listing.cardImageUrl,
              category: listing.category,
              iconSize: 96 * 0.45,
            ),
            if (badge != null)
              Positioned(
                top: AppSpacing.sm,
                left: 0,
                right: AppSpacing.xs,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ListingRibbon(badge: badge, listing: listing),
                  ),
                ),
              ),
            PhotoDistance(pin: listing.pickupLocation),
          ],
        ),
      ),
    );
  }
}

// Puts Non-Halal beside the name, or under it when both don't fit on one line.
class _NameLine extends StatelessWidget {
  const _NameLine({required this.listing});

  static const String nonHalal = 'Non-Halal';

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    if (listing.isHalal != false) {
      return Text(
        listing.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: nameStyle,
      );
    }

    final pill = _Pill(
      key: const ValueKey('non-halal'),
      text: nonHalal,
      color: theme.colorScheme.onSurface,
      fill: AppColors.field,
    );
    final name = Text(
      listing.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: nameStyle,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        double widthOf(String text, TextStyle? style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final pillWidth =
            widthOf(nonHalal, _Pill.textStyle(context, null)) +
            AppSpacing.sm * 2;
        final fits =
            widthOf(listing.title, nameStyle) + AppSpacing.sm + pillWidth <=
            constraints.maxWidth;

        if (fits) {
          return Row(
            children: [
              Flexible(child: name),
              const SizedBox(width: AppSpacing.sm),
              pill,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [name, const SizedBox(height: 2), pill],
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.text,
    required this.color,
    required this.fill,
  });

  final String text;
  final Color color;
  final Color fill;

  static TextStyle? textStyle(BuildContext context, Color? color) =>
      Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: color, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(text, style: textStyle(context, color)),
      ),
    );
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
        children: [
          Icon(icon, size: 13 * iconScale(context), color: AppColors.textMuted),
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
