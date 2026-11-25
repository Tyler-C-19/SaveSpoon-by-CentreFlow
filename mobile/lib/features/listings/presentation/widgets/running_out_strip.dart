import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/listing.dart';
import 'listing_card.dart';

class RunningOutStrip extends StatelessWidget {
  const RunningOutStrip({
    super.key,
    required this.listings,
    this.onOpen,
    this.onShowVendor,
    this.onPressDown,
    this.actionsFor,
    this.actionsWidth = 0,
  });

  final List<Listing> listings;
  final ValueChanged<Listing>? onOpen;
  final ValueChanged<Listing>? onShowVendor;
  final ValueChanged<Listing>? onPressDown;
  // Customer cards only: buttons such as the heart.
  final Widget Function(Listing listing)? actionsFor;
  final double actionsWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: actionsFor == null
          ? ListingCard.browseHeight
          : ListingCard.heightWithActions(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth =
              (constraints.maxWidth - AppSpacing.md * 2 - AppSpacing.sm) / 2;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: listings.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) => SizedBox(
              width: cardWidth,
              child: ListingCard(
                listing: listings[index],
                showBadges: true,
                onTap: onOpen == null ? null : () => onOpen!(listings[index]),
                onShowVendor: onShowVendor == null
                    ? null
                    : () => onShowVendor!(listings[index]),
                onPressDown: onPressDown == null
                    ? null
                    : () => onPressDown!(listings[index]),
                actions: actionsFor?.call(listings[index]),
                actionsWidth: actionsWidth,
              ),
            ),
          );
        },
      ),
    );
  }
}
