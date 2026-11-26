import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../listings/presentation/widgets/icon_scale.dart';
import '../../../seller_profile/domain/geo_point.dart';
import '../../domain/distance.dart';
import '../providers/user_location_provider.dart';

// Vendors look at their own listings, so they never see distances.
bool _isVendor(BuildContext context) =>
    context.read<AuthProvider?>()?.user?.role == 'vendor';

// A small white pill with the distance, for the bottom-left corner of a food
// photo. Nothing shows without the customer's location.
class DistancePill extends StatelessWidget {
  const DistancePill({super.key, required this.pin});

  final GeoPoint? pin;

  static TextStyle? textStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700);

  // Size of a photo pill with [text], such as the Save pill beside this one.
  static Size pillSize(BuildContext context, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: textStyle(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final size = Size(
      painter.width + AppSpacing.sm * 2,
      painter.height + AppSpacing.xs * 2,
    );
    painter.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    if (_isVendor(context)) return const SizedBox.shrink();
    final here = context.watch<UserLocationProvider?>()?.position;
    final distance = distanceBetween(here, pin);
    if (distance == null) return const SizedBox.shrink();
    return DecoratedBox(
      key: const ValueKey('distance-pill'),
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.near_me_outlined,
              size: 12 * iconScale(context),
              color: AppColors.primary,
            ),
            const SizedBox(width: 2),
            Text(
              distance,
              key: const ValueKey('distance-text'),
              maxLines: 1,
              softWrap: false,
              style: textStyle(context),
            ),
          ],
        ),
      ),
    );
  }
}

// Puts the distance pill in a photo's bottom-left corner, leaving room for a
// pill on the right ([besideText], such as "Save 44%"). When there is no room
// beside it, it sits just above that pill instead; it shrinks rather than
// overlap. Goes straight in the photo's Stack.
class PhotoDistance extends StatelessWidget {
  const PhotoDistance({super.key, required this.pin, this.besideText});

  static const double _minWidth = 32;

  final GeoPoint? pin;
  final String? besideText;

  @override
  Widget build(BuildContext context) {
    final beside = besideText;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final full = constraints.maxWidth - AppSpacing.sm * 2;
          final besideSize = beside == null
              ? Size.zero
              : DistancePill.pillSize(context, beside);
          var room =
              full - (beside == null ? 0 : besideSize.width + AppSpacing.sm);
          var lift = 0.0;
          if (room < _minWidth) {
            room = full;
            lift = besideSize.height + AppSpacing.xs;
          }
          final height = DistancePill.pillSize(context, '0 m').height;
          final tooLow =
              constraints.maxHeight < lift + height + AppSpacing.sm * 2;
          if (room < _minWidth || tooLow) return const SizedBox.shrink();
          return Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm + lift,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: room),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: DistancePill(pin: pin),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// "350 m away" on its own green line, for an address. Nothing without the
// customer's location.
class DistanceLine extends StatelessWidget {
  const DistanceLine({super.key, required this.pin});

  final GeoPoint? pin;

  @override
  Widget build(BuildContext context) {
    final away = distanceAwayFrom(context, pin);
    if (away == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('distance-line'),
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            Icons.near_me_outlined,
            size: 14 * iconScale(context),
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              away,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// "350 m away" for one pin, or null.
String? distanceAwayFrom(BuildContext context, GeoPoint? pin) {
  if (_isVendor(context)) return null;
  final here = context.watch<UserLocationProvider?>()?.position;
  final distance = distanceBetween(here, pin);
  return distance == null ? null : '$distance away';
}
