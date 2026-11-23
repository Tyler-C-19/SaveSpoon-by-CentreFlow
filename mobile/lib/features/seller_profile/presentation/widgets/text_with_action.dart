import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

// A small green button such as Directions or Call.
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = true,
  });

  static const double _iconSize = 16;

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  // False draws only the icon and words, with no green background.
  final bool filled;

  static TextStyle? _labelStyle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w700,
    );
  }

  // How wide the pill draws, so a line can tell whether it fits beside text.
  double widthIn(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _labelStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    final iconWidth = icon == null ? 0 : _iconSize + AppSpacing.xs;
    return width + iconWidth + AppSpacing.sm * 2;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = this.icon;
    return Material(
      color: filled ? AppColors.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: _iconSize, color: colors.primary),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(child: Text(label, style: _labelStyle(context))),
            ],
          ),
        ),
      ),
    );
  }
}

// Text with its button at the right end of the same line, or on its own line
// at the right when both don't fit.
class TextWithAction extends StatelessWidget {
  const TextWithAction({
    super.key,
    required this.text,
    this.style,
    this.action,
  });

  final String text;
  final TextStyle? style;
  final ActionPill? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    final label = Text(text, style: style);
    if (action == null) return label;

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final textWidth = painter.width;
        painter.dispose();
        final fits =
            textWidth + AppSpacing.sm + action.widthIn(context) <=
            constraints.maxWidth;

        if (fits) {
          return Row(
            children: [
              Expanded(child: label),
              const SizedBox(width: AppSpacing.sm),
              action,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            const SizedBox(height: AppSpacing.xs),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        );
      },
    );
  }
}
