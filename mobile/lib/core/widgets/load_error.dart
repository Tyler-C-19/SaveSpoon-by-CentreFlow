import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../theme/app_theme.dart';

// A failed load with a Try Again button. Server-down messages get a plug icon.
class LoadError extends StatelessWidget {
  const LoadError({
    super.key,
    required this.message,
    required this.onRetry,
    this.title,
  });

  final String message;
  final VoidCallback onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final serverDown = ServerMessages.all.contains(message);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          serverDown ? Icons.power_off_outlined : Icons.error_outline,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.md),
        if (title != null) ...[
          Text(
            title!,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton(onPressed: onRetry, child: const Text('Try Again')),
      ],
    );
  }
}
