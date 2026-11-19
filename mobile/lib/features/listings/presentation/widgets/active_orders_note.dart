import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

// A short line under something active orders have locked, with a way to see them.
class ActiveOrdersNote extends StatelessWidget {
  const ActiveOrdersNote({super.key, required this.count, this.onViewOrders});

  final int count;
  final VoidCallback? onViewOrders;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              count == 1
                  ? 'Locked while 1 order is active.'
                  : 'Locked while $count orders are active.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.textMuted),
            ),
          ),
          if (onViewOrders != null)
            TextButton(
              key: const ValueKey('view-active-orders'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onViewOrders,
              child: const Text('View Active Orders'),
            ),
        ],
      ),
    );
  }
}
