import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/external_links.dart';
import '../../../seller_profile/presentation/widgets/text_with_action.dart';
import '../../domain/cart.dart';

// Directions sits at the right, under a stall name too long to share a line.
class CartStallHeading extends StatelessWidget {
  const CartStallHeading({
    super.key,
    required this.stallName,
    required this.items,
  });

  final String stallName;
  final List<CartItem> items;

  @override
  Widget build(BuildContext context) {
    final pinned = items.where((item) => item.pickupLocation != null);
    final item = pinned.isEmpty ? null : pinned.first;
    final location = item?.pickupLocation;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: TextWithAction(
        text: 'From $stallName',
        style: Theme.of(context).textTheme.titleSmall,
        action: location == null
            ? null
            : ActionPill(
                key: ValueKey('cart-find-on-maps-$stallName'),
                label: directionsLabel,
                icon: directionsIcon,
                filled: false,
                onTap: () => openDirections(
                  lat: location.lat,
                  lng: location.lng,
                  placeId: item?.pickupPlaceId,
                  address: item?.pickupAddress,
                  context: context,
                ),
              ),
      ),
    );
  }
}
