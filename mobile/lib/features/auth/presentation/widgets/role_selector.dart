import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class RoleSelector extends StatelessWidget {
  const RoleSelector({super.key, required this.role, required this.onChanged});

  final String role;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'I want to join as',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _RoleCard(
                title: 'Vendor',
                icon: Icons.storefront_outlined,
                description: 'Sell leftover stock',
                selected: role == 'vendor',
                onTap: () => onChanged('vendor'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _RoleCard(
                title: 'Customer',
                icon: Icons.shopping_bag_outlined,
                description: 'Buy surplus food',
                selected: role == 'customer',
                onTap: () => onChanged('customer'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.icon,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? colors.primaryContainer : AppColors.field,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? colors.primary : AppColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(title, style: theme.textTheme.titleMedium),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
