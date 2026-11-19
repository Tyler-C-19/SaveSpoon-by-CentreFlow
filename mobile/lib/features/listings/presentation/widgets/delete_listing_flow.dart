import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/listing_repository.dart';
import '../../domain/listing.dart';

// Blocked while the listing has active orders; otherwise two warnings, then
// a permanent delete. Returns true once the listing is gone.
Future<bool> runDeleteListingFlow(
  BuildContext context, {
  required ListingRepository repository,
  required Listing listing,
  required int activeOrders,
}) async {
  if (activeOrders > 0) {
    await _showBlocked(context, listing, activeOrders);
    return false;
  }
  if (!await _confirm(context, listing) || !context.mounted) return false;
  if (!await _confirmAgain(context, listing) || !context.mounted) return false;

  try {
    await repository.delete(listing.id);
    return true;
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    if (e.code == 'ACTIVE_ORDERS') {
      try {
        final own = await repository.fetchMineOne(listing.id);
        if (context.mounted) {
          await _showBlocked(context, own.listing, own.activeOrderCount);
        }
        return false;
      } on ApiException {
        // Falls through to the server's own message.
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
}

Future<void> _showBlocked(BuildContext context, Listing listing, int count) {
  final end = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(listing.pickupEnd));
  final orders = count == 1 ? '1 active order' : '$count active orders';
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Can't Delete Yet"),
      content: Text(
        'You have $orders for ${listing.title}. '
        'You can delete it after pickup ends at $end.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(BuildContext context, Listing listing) async {
  final colors = Theme.of(context).colorScheme;
  final error = colors.error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this listing?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customers will no longer be able to see or order '
              '${listing.title}.',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Sales figures for this item are kept.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: error),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      "Deletion is permanent and can't be undone.",
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<bool> _confirmAgain(BuildContext context, Listing listing) async {
  final error = Theme.of(context).colorScheme.error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: error, size: 36),
      title: const Text('Are you sure?'),
      content: Text(
        '${listing.title} will be permanently deleted. '
        "You won't be able to recover it.",
        style: TextStyle(color: error, fontWeight: FontWeight.w600),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep Listing'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Listing'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
