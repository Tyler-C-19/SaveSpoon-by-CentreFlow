import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../theme/app_theme.dart';

// Shows over every screen while the server is starting up or slow to answer.
class ServerWakeBanner extends StatelessWidget {
  const ServerWakeBanner({
    super.key,
    required this.serverWait,
    required this.child,
  });

  static const wakingMessage =
      'Waking up the server. This can take up to a minute.';
  static const slowMessage =
      'This is taking longer than usual. Please wait a moment.';
  static const bannerKey = ValueKey('server-wake-banner');

  final ValueListenable<ServerWait> serverWait;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: ValueListenableBuilder<ServerWait>(
              valueListenable: serverWait,
              builder: (context, wait, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: switch (wait) {
                  ServerWait.none => const SizedBox.shrink(),
                  ServerWait.waking => const _Banner(wakingMessage),
                  ServerWait.slow => const _Banner(slowMessage),
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      key: ServerWakeBanner.bannerKey,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.primaryPale,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.primarySoft),
            boxShadow: AppShadows.card,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + AppSpacing.xs,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
