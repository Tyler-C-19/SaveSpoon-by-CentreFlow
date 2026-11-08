import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/listing.dart';
import '../../domain/listing_validators.dart';

class AllergenPicker extends StatelessWidget {
  const AllergenPicker({
    super.key,
    required this.selected,
    required this.onToggled,
    required this.otherAllergens,
    required this.onSuggest,
    required this.isSuggesting,
    required this.usedAi,
    required this.confirmed,
    required this.onConfirmed,
    this.foundNothing = false,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggled;
  final TextEditingController otherAllergens;
  final VoidCallback onSuggest;
  final bool isSuggesting;
  final bool usedAi;
  final bool confirmed;
  final ValueChanged<bool> onConfirmed;
  final bool foundNothing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Allergens',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Let AI suggest them from your item name and description.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: 'Suggest allergens with SaveSpoon AI',
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                onPressed: isSuggesting ? null : onSuggest,
                icon: isSuggesting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(isSuggesting ? 'Thinking…' : 'SaveSpoon AI'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final allergen in ListingOptions.allergens)
              FilterChip(
                label: Text(allergenLabel(allergen)),
                selected: selected.contains(allergen),
                onSelected: (_) => onToggled(allergen),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: 'Other allergens (optional)',
          controller: otherAllergens,
          validator: ListingValidators.otherAllergens,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Separate with commas, such as "Cashew, Almond". '
          'Leave empty for "None declared".',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.textMuted),
        ),
        if (usedAi) ...[
          const SizedBox(height: AppSpacing.sm),
          Material(
            color: AppColors.warningPale,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: AppColors.onWarning,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          foundNothing
                              ? "SaveSpoon AI found no allergens, but that doesn't "
                                    'mean the food is free of them. SaveSpoon AI can '
                                    'make mistakes. Check these allergens before saving.'
                              : 'SaveSpoon AI can make mistakes. Check these '
                                    'allergens before saving.',
                          style: const TextStyle(color: AppColors.onWarning),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      "I've checked the allergens",
                      style: TextStyle(color: AppColors.onWarning),
                    ),
                    value: confirmed,
                    onChanged: (value) => onConfirmed(value ?? false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
