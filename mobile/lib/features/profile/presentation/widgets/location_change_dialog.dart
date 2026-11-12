import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../data/profile_repository.dart';

// Warns that a new pickup location also applies to every listing.
Future<bool> confirmLocationChange(BuildContext context) async {
  final int count;
  try {
    count = (await context.read<ProfileRepository>().summary()).listingCount;
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
  if (count == 0) return true;
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Change pickup location?'),
      content: Text(
        'This changes the pickup location on all $count of your '
        'listing${count == 1 ? '' : 's'}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Change Location'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
