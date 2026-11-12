import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/profile_repository.dart';
import '../../domain/user_profile.dart';
import '../widgets/delete_account_flow.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_heading.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _scroll = ScrollController();
  UserProfile? _profile;
  String? _error;
  String? _banner;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  // The tab shell turns tickers off for tabs that aren't showing, so this
  // clears the banner once My Profile is left for another tab.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled && _banner != null) {
      _banner = null;
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    try {
      final profile = await context.read<ProfileRepository>().fetch();
      if (!mounted) return;
      final url = profile.photoUrl;
      if (url != null && url != _profile?.photoUrl) {
        // Loads the new picture first, so the old one stays until it's ready.
        await precacheImage(
          NetworkImage(url),
          context,
          onError: (_, _) {},
        ).timeout(const Duration(seconds: 10), onTimeout: () {});
        if (!mounted) return;
      }
      setState(() {
        _profile = profile;
        _error = null;
      });
      // Keeps the saved user, and the name shown elsewhere, up to date.
      final saved = auth.user;
      final fresh = profile.user;
      if (saved != null &&
          (saved.name != fresh.name ||
              saved.email != fresh.email ||
              saved.phone != fresh.phone)) {
        await auth.updateUser(fresh);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  // The page closes with a message, or a ProfileChange, when something
  // changed. The profile is read again either way, since a lock may have
  // started.
  Future<void> _open(String location, {Object? extra}) async {
    // Leaving My Profile for another page also clears the banner.
    setState(() => _banner = null);
    final result = await context.push<Object?>(location, extra: extra);
    if (!mounted) return;
    final message = switch (result) {
      ProfileChange change => change.message,
      String text => text,
      _ => null,
    };
    // Shown at once, so the old picture isn't seen while the page closes.
    if (result is ProfileChange && result.profile != null) {
      setState(() => _profile = result.profile);
    }
    await _closingFinished();
    if (!mounted) return;
    if (message == null) return _load();
    setState(() => _banner = message);
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    }
    await _load();
  }

  // Updating the user refreshes the router, which must wait until the
  // closing page has gone. The tab sits inside the shell, so this watches
  // the shell's own page.
  Future<void> _closingFinished() {
    final shell = ModalRoute.of(Navigator.of(context).context);
    final animation = shell?.secondaryAnimation;
    if (animation == null || animation.isDismissed) return Future.value();
    final done = Completer<void>();
    void listener(AnimationStatus status) {
      if (status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(listener);
      done.complete();
    }

    animation.addStatusListener(listener);
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = _profile?.user ?? auth.user;
    if (user == null) return const SizedBox.shrink();

    final profile = _profile;
    final role = user.role;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    const gap = SizedBox(height: AppSpacing.md);
    final locked = profile?.isLocked() ?? false;
    // The floating nav bar's height, given to the body by the tab shell.
    final navBar = MediaQuery.paddingOf(context).bottom;
    const fade = 32.0;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              navBar + fade + AppSpacing.md,
            ),
            children: [
              const ProfileHeading(
                title: 'My Profile',
                caption: 'Manage your profile details here',
              ),
              const SizedBox(height: AppSpacing.md),
              if (_banner != null) ...[
                _ChangeBanner(
                  message: _banner!,
                  onClose: () => setState(() => _banner = null),
                ),
                gap,
              ],
              Center(
                child: ProfileAvatar(
                  isLoading: profile == null && _error == null,
                  name: user.name,
                  photoUrl: profile?.photoUrl,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                user.name,
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                _LoadError(message: _error!, onRetry: _load),
                gap,
              ],
              _Section(
                title: 'Account Details',
                onEdit: () => _open(AppRoutes.profileEditFor(role)),
                editLabel: 'Edit account details',
                children: [
                  _Row(
                    icon: Icons.badge_outlined,
                    label: 'Account type',
                    value: role == 'vendor' ? 'Vendor' : 'Customer',
                  ),
                  _Row(
                    icon: Icons.email_outlined,
                    label: 'Email',
                    value: user.email,
                  ),
                  _Row(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: user.phone ?? '-',
                  ),
                  if (profile != null && !profile.canChangeEmail)
                    const _Note(
                      "Your email is linked to Google, so it can't be changed "
                      'here.',
                    ),
                ],
              ),
              gap,
              _Section(
                title: 'Password',
                children: [
                  if (profile == null || profile.hasPassword) ...[
                    const _Row(
                      icon: Icons.lock_outline,
                      label: 'Password',
                      value: '••••••••',
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: profile == null || locked
                            ? null
                            : () => _open(AppRoutes.profilePasswordFor(role)),
                        child: const Text('Change Password'),
                      ),
                    ),
                    if (locked) _Note(profile!.lockMessage, isWarning: true),
                  ] else
                    const _Note('Signed in with Google, no password.'),
                ],
              ),
              if (role == 'vendor' && profile?.vendor != null) ...[
                gap,
                _Section(
                  title: 'Vendor Details',
                  onEdit: () => _open(
                    AppRoutes.vendorBusinessEdit,
                    extra: profile.vendor,
                  ),
                  editLabel: 'Edit vendor details',
                  children: [
                    _Row(
                      icon: Icons.storefront_outlined,
                      label: 'Vendor name',
                      value: profile!.vendor!.businessName,
                    ),
                    _Row(
                      icon: Icons.phone_outlined,
                      label: 'Contact number',
                      value: profile.vendor!.phone,
                    ),
                    _Row(
                      icon: Icons.location_on_outlined,
                      label: 'Pickup address',
                      value: profile.vendor!.address,
                    ),
                    _Row(
                      icon: Icons.notes_outlined,
                      label: 'Description',
                      value: profile.vendor!.description.isEmpty
                          ? 'None yet'
                          : profile.vendor!.description,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: auth.logout,
                icon: const Icon(Icons.logout),
                label: const Text('Log Out'),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: profile == null
                    ? null
                    : () async {
                        await runDeleteAccountFlow(context, profile);
                        if (mounted) await _load();
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Account'),
              ),
            ],
          ),
        ),
        // Hides what scrolls behind the nav bar, with a soft edge above it.
        // Only on this tab for now; the other tabs get it in UI refinement.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: navBar + fade,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.page.withValues(alpha: 0),
                    AppColors.page,
                    AppColors.page,
                  ],
                  stops: [0, fade / (navBar + fade), 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.onEdit,
    this.editLabel,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onEdit;
  final String? editLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: editLabel,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                )
              else
                const SizedBox(height: 48),
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        right: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.isWarning = false});

  final String text;

  // Shown in red with a lock, for the password lock.
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(
        right: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      child: isWarning
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_clock_outlined, size: 18, color: error),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(color: error, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          : Text(text, style: const TextStyle(color: AppColors.textMuted)),
    );
  }
}

class _ChangeBanner extends StatelessWidget {
  const _ChangeBanner({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryPale,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, color: AppColors.primary),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
