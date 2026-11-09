import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/listing.dart';
import 'listing_card.dart';

class RunningOutStrip extends StatelessWidget {
  const RunningOutStrip({super.key, required this.listings, this.onOpen});

  final List<Listing> listings;
  final ValueChanged<Listing>? onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ListingCard.browseHeight,
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
              ),
            ),
          );
        },
      ),
    );
  }
}
