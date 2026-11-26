import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../cart/presentation/providers/cart_provider.dart';
import '../../domain/listing.dart';
import '../pages/food_details_page.dart' show addToCartFailed;
import 'favourite_button.dart';
import 'icon_scale.dart';

// Trial: adds one of the item to the cart straight from a card or row.
class QuickAddButton extends StatefulWidget {
  const QuickAddButton({
    super.key,
    required this.listing,
    this.size = ListingIconButton.compactSize,
  });

  final Listing listing;
  final double size;

  @override
  State<QuickAddButton> createState() => _QuickAddButtonState();
}

class _QuickAddButtonState extends State<QuickAddButton> {
  bool _adding = false;

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final router = GoRouter.maybeOf(context);
    setState(() => _adding = true);
    String message;
    var added = false;
    try {
      message = await context.read<CartProvider>().addItem(
        widget.listing.id,
        1,
      );
      added = true;
    } on ApiException catch (e) {
      final status = e.statusCode;
      message = status == null || status >= 500 ? addToCartFailed : e.message;
    } finally {
      if (mounted) setState(() => _adding = false);
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          persist: false,
          action: added && router != null
              ? SnackBarAction(
                  label: 'View Cart',
                  onPressed: () => router.go(AppRoutes.customerCart),
                )
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListingIconButton(
      key: ValueKey('quick-add-${widget.listing.id}'),
      icon: Icons.add_shopping_cart,
      color: Theme.of(context).colorScheme.primary,
      label: 'Add to Cart',
      size: widget.size,
      onPressed: _adding ? null : _add,
    );
  }
}

// The heart beside the cart button, at the bottom right of a card or row.
class ListingActions extends StatelessWidget {
  const ListingActions({super.key, required this.listing});

  final Listing listing;

  // How much room the two buttons take, at the current text size.
  static double widthOf(BuildContext context) =>
      ListingIconButton.compactSize * 2 * iconScale(context);

  @override
  Widget build(BuildContext context) {
    return Row(
      key: ValueKey('listing-actions-${listing.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        FavouriteButton(listingId: listing.id),
        QuickAddButton(listing: listing),
      ],
    );
  }
}
