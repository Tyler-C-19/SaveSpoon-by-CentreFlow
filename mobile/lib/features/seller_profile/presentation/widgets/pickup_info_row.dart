import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'text_with_action.dart';

// An info line with its button at the right; the button moves under the
// value when both don't fit, so long text never squeezes it.
class PickupInfoRow extends StatelessWidget {
  const PickupInfoRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.actionKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = this.actionLabel;
    final onAction = this.onAction;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                TextWithAction(
                  text: value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  action: actionLabel == null || onAction == null
                      ? null
                      : ActionPill(
                          key: actionKey,
                          label: actionLabel,
                          icon: actionIcon,
                          onTap: onAction,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
