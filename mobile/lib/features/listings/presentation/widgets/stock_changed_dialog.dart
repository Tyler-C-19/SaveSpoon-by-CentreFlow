import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

// Asks whether to set the stock anyway after orders changed it while editing.
// True: set it to [wanted]. False or null: keep [current].
Future<bool?> askAboutStockChange(
  BuildContext context, {
  required String message,
  required int current,
  required int wanted,
}) {
  final reason = message.endsWith('.')
      ? message.substring(0, message.length - 1)
      : message;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Stock Changed'),
      content: Text('$reason, Set it to $wanted anyway?'),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Keep $current'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('Set to $wanted'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
