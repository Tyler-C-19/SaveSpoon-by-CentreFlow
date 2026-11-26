import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/error_text.dart';
import '../../../profile/presentation/widgets/profile_heading.dart';
import '../../data/notification_repository.dart';
import '../../domain/app_notification.dart';
import '../providers/notifications_controller.dart';
import '../widgets/notification_settings_section.dart';

const savedMessage = 'Notification settings saved.';

// Like Edit Account Details: the switches, and Save Changes once something
// changes. Closing after a save returns the message for My Profile. While
// notifications are off on the phone, only the note to turn them on shows.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, required this.role});

  final String role;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  NotificationPrefs? _saved;
  NotificationPrefs? _draft;
  String? _loadError;
  String? _saveError;
  bool _saving = false;
  bool _askedAgain = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await context.read<NotificationRepository>().fetchPrefs();
      if (!mounted) return;
      setState(() {
        _saved = prefs;
        _draft = prefs;
        _loadError = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  bool get _changed {
    final saved = _saved;
    final draft = _draft;
    return saved != null && draft != null && !draft.sameAs(saved);
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final controller = context.read<NotificationsController?>();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await context.read<NotificationRepository>().savePrefs(_draft!);
      await controller?.syncReminders();
      if (mounted) navigator.pop(savedMessage);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e.message;
      });
    }
  }

  Future<void> _turnOn(NotificationsController controller) async {
    if (_askedAgain) return controller.openSettings();
    final on = await controller.turnOn();
    if (mounted && !on) setState(() => _askedAgain = true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationsController?>();
    final draft = _draft;
    final off = controller != null && !controller.permitted;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: draft == null
            ? Center(
                child: _loadError == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ErrorText(_loadError),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const ProfileHeading(
                      title: 'Notification Settings',
                      caption:
                          'Choose which notifications SaveSpoon sends to your '
                          'phone. All of them still appear in your in-app '
                          'inbox.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    NotificationStateSwitcher(
                      child: off
                          ? NotificationsOffNote(
                              key: const ValueKey('off'),
                              askedAgain: _askedAgain,
                              onTurnOn: () => _turnOn(controller),
                            )
                          : Column(
                              key: const ValueKey('on'),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final item in notificationSwitchesFor(
                                  widget.role,
                                ))
                                  _SwitchRow(
                                    item: item,
                                    value: draft.isOn(item.key),
                                    onChanged: _saving
                                        ? null
                                        : (on) => setState(
                                            () => _draft = draft.withValue(
                                              item.key,
                                              on,
                                            ),
                                          ),
                                  ),
                                if (controller != null)
                                  _PhoneSettingsRow(
                                    onTap: controller.openSettings,
                                  ),
                                const SizedBox(height: AppSpacing.lg),
                                ErrorText(_saveError),
                                AppButton(
                                  key: const ValueKey(
                                    'notification-settings-save',
                                  ),
                                  label: 'Save Changes',
                                  isLoading: _saving,
                                  onPressed: _changed ? _save : null,
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// Opens SaveSpoon in the phone's Settings, to turn all its notifications on or
// off, or change their sound and vibration.
class _PhoneSettingsRow extends StatelessWidget {
  const _PhoneSettingsRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      key: const ValueKey('phone-notification-settings'),
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            const Icon(
              Icons.phone_android_outlined,
              size: 20,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Phone settings', style: textTheme.bodyLarge),
                  Text(
                    'Turn all SaveSpoon notifications on or off, or change '
                    'their sound',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Icon(Icons.open_in_new, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.item,
    required this.value,
    required this.onChanged,
  });

  final NotificationSwitch item;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: [
            Icon(item.icon, size: 20, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label, style: textTheme.bodyLarge),
                  Text(
                    item.caption,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Switch(
              key: ValueKey('notification-switch-${item.key}'),
              value: value,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
