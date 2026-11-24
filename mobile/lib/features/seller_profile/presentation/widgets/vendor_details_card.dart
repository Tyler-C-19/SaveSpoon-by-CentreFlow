import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../profile/presentation/widgets/profile_avatar.dart';
import '../../domain/vendor_info.dart';

// The stall on Food Details with its pickup and contact rows. Tapping the
// stall opens the vendor pane; the picture fills in once the vendor info
// arrives.
class VendorDetailsCard extends StatelessWidget {
  const VendorDetailsCard({
    super.key,
    required this.stallName,
    required this.onTap,
    this.info,
    this.details = const [],
  });

  final String stallName;
  final VendorInfo? info;
  final VoidCallback onTap;
  // Rows under the stall, such as the pickup address and contact number.
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 22, color: colors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Vendor Details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            key: const ValueKey('vendor-details-card'),
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  ProfileAvatar(
                    name: stallName,
                    photoUrl: info?.photoUrl,
                    size: 44,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      stallName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          if (details.isNotEmpty) ...[
            const Divider(height: AppSpacing.lg),
            ...details,
          ],
        ],
      ),
    );
  }
}
