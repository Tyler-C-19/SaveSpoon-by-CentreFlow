import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../listings/presentation/widgets/icon_scale.dart';
import '../../data/position_source.dart';
import '../providers/user_location_provider.dart';

// Says why no distance shows, with the one action that can fix it.
// Shows nothing when location is fully allowed.
class LocationNote extends StatelessWidget {
  const LocationNote({super.key, this.padding = EdgeInsets.zero});

  final EdgeInsetsGeometry padding;

  static const String approximate =
      'Using approximate location, so distances are estimates.';
  static const String denied = 'Allow location to discover food near you.';
  static const String deniedForever =
      'Location permissions are off for SaveSpoon. Allow them in Settings to '
      'discover food near you.';
  static const String serviceOff =
      "Your phone's location is off. Turn it on to discover food near you.";

  @override
  Widget build(BuildContext context) {
    final location = context.watch<UserLocationProvider?>();
    if (location == null) return const SizedBox.shrink();
    final (
      String message,
      String? action,
      VoidCallback? onAction,
    ) = switch (location.access) {
      LocationAccess.allowed when location.approximate => (
        approximate,
        null,
        null,
      ),
      LocationAccess.denied => (
        denied,
        'Allow Location',
        location.requestAndLocate,
      ),
      LocationAccess.deniedForever => (
        deniedForever,
        'Open Settings',
        location.source.openAppSettings,
      ),
      LocationAccess.serviceOff => (
        serviceOff,
        'Turn On Location',
        location.source.openLocationSettings,
      ),
      _ => ('', null, null),
    };
    if (message.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textMuted,
    );
    return Padding(
      padding: padding,
      child: Row(
        key: const ValueKey('location-note'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16 * iconScale(context),
            color: AppColors.textMuted,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: muted),
                if (action != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: onAction, child: Text(action)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
