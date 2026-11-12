import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/error_text.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/profile_repository.dart';
import '../../domain/user_profile.dart';

const String accountDeletedMessage = 'Your account has been deleted.';

// Checks for blocks, warns, asks again, confirms identity, then deletes and
// logs out.
Future<void> runDeleteAccountFlow(
  BuildContext context,
  UserProfile profile,
) async {
  final repository = context.read<ProfileRepository>();
  final auth = context.read<AuthProvider>();
  final messenger = ScaffoldMessenger.of(context);

  if (profile.hasPassword && profile.isLocked()) {
    await _showBlocked(
      context,
      'Account deletion is ${profile.lockMessage[0].toLowerCase()}'
      '${profile.lockMessage.substring(1)}',
      title: 'Too many wrong tries',
    );
    return;
  }

  final AccountSummary summary;
  try {
    summary = await repository.summary();
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;

  if (summary.blocksDeletion) {
    await _showBlocked(context, summary.blockedMessage);
    return;
  }

  if (!await _confirmWarning(context, profile, summary)) return;
  if (!context.mounted) return;
  if (!await _confirmAgain(context)) return;
  if (!context.mounted) return;

  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConfirmIdentityDialog(
      repository: repository,
      hasPassword: profile.hasPassword,
    ),
  );
  if (deleted != true) return;

  messenger.showSnackBar(const SnackBar(content: Text(accountDeletedMessage)));
  await auth.logout();
}

Future<void> _showBlocked(
  BuildContext context,
  String message, {
  String title = "You can't delete your account yet",
}) => showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK'),
      ),
    ],
  ),
);

Future<bool> _confirmWarning(
  BuildContext context,
  UserProfile profile,
  AccountSummary summary,
) async {
  final isVendor = profile.user.role == 'vendor';
  final listings = summary.listingCount;
  final items = [
    'Your account and its details',
    if (isVendor) 'Your vendor details',
    if (isVendor && listings > 0)
      'Your $listings listing${listings == 1 ? '' : 's'}',
    if (!isVendor) 'Your cart',
    if (profile.photoUrl != null) 'Your profile picture',
  ];
  final colors = Theme.of(context).colorScheme;
  final error = colors.error;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This deletes:'),
            const SizedBox(height: AppSpacing.sm),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Past orders are kept so sales records stay correct.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: error),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: error),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      "Deletion is permanent and can't be undone.",
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

Future<bool> _confirmAgain(BuildContext context) async {
  final error = Theme.of(context).colorScheme.error;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: error, size: 36),
      title: const Text('Are you sure?'),
      content: Text(
        'Your account will be permanently deleted. '
        "You won't be able to recover it.",
        style: TextStyle(color: error, fontWeight: FontWeight.w600),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep My Account'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Yes, Delete Permanently'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _ConfirmIdentityDialog extends StatefulWidget {
  const _ConfirmIdentityDialog({
    required this.repository,
    required this.hasPassword,
  });

  final ProfileRepository repository;
  final bool hasPassword;

  @override
  State<_ConfirmIdentityDialog> createState() => _ConfirmIdentityDialogState();
}

class _ConfirmIdentityDialogState extends State<_ConfirmIdentityDialog> {
  final _input = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final text = widget.hasPassword ? _input.text : _input.text.trim();
    if (widget.hasPassword && text.isEmpty) {
      return setState(() => _error = 'Enter your password.');
    }
    if (!widget.hasPassword && text != 'DELETE') {
      return setState(() => _error = 'Type DELETE to confirm.');
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await widget.repository.deleteAccount(
        password: widget.hasPassword ? text : null,
        confirm: widget.hasPassword ? null : text,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: const Text('Confirm deletion'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.hasPassword
                  ? 'Enter your password to delete your account.'
                  : 'Type DELETE to delete your account.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: widget.hasPassword ? 'Password' : 'Type DELETE',
              icon: widget.hasPassword
                  ? Icons.lock_outline
                  : Icons.delete_outline,
              controller: _input,
              isPassword: widget.hasPassword,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSpacing.md),
            ErrorText(_error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: error),
          onPressed: _isLoading ? null : _delete,
          child: _isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete Permanently'),
        ),
      ],
    );
  }
}
