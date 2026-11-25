import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/favourites_provider.dart';
import 'icon_scale.dart';

const String favouriteFailed =
    "Couldn't update your Favourites. Please try again.";

// Shows the server's reason when it gives one, such as the 200 limit.
String favouriteFailure(Object error) =>
    error is ApiException && error.code == 'FAVOURITES_FULL'
    ? error.message
    : favouriteFailed;

class FavouriteButton extends StatelessWidget {
  const FavouriteButton({
    super.key,
    required this.listingId,
    this.size = ListingIconButton.compactSize,
    this.maxSize = double.infinity,
  });

  final String listingId;
  final double size;
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    final favourite = context.select<FavouritesProvider, bool>(
      (favourites) => favourites.isFavourite(listingId),
    );
    final colors = Theme.of(context).colorScheme;
    return ListingIconButton(
      key: ValueKey('favourite-$listingId'),
      icon: favourite ? Icons.favorite : Icons.favorite_border,
      color: favourite ? colors.error : AppColors.textMuted,
      label: favourite ? 'Remove from Favourites' : 'Add to Favourites',
      size: size,
      maxSize: maxSize,
      onPressed: () => _toggle(context),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<FavouritesProvider>().toggle(listingId);
    } catch (e) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(favouriteFailure(e))));
    }
  }
}

// A small round icon button for cards and rows. It takes its own taps, and a
// long-press only shows its name, so the card underneath doesn't open.
class ListingIconButton extends StatelessWidget {
  const ListingIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
    this.size = compactSize,
    this.maxSize = double.infinity,
  });

  static const double compactSize = 32;

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  // Grows with the text, but never past this, such as in a top bar.
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    final dimension = math.min(size * iconScale(context), maxSize);
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onPressed,
          radius: dimension / 2 + 4,
          child: SizedBox.square(
            dimension: dimension,
            child: Icon(
              icon,
              size: dimension * 0.62,
              color: onPressed == null ? AppColors.textMuted : color,
            ),
          ),
        ),
      ),
    );
  }
}
