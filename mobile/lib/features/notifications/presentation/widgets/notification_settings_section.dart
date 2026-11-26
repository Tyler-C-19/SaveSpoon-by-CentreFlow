import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/notification_repository.dart';
import '../../domain/app_notification.dart';
import '../providers/notifications_controller.dart';

class NotificationSwitch {
  const NotificationSwitch(this.key, this.label, this.caption, this.icon);

  final String key;
  final String label;
  final String caption;
  final IconData icon;
}

const _vendorSwitches = [
  NotificationSwitch(
    NotificationPrefs.orderAlerts,
    'Order alerts',
    'New orders and cancellations',
    Icons.receipt_long_outlined,
  ),
  NotificationSwitch(
    NotificationPrefs.stockAlerts,
    'Stock alerts',
    'When an item is running low or out of stock',
    Icons.inventory_2_outlined,
  ),
];

const _customerSwitches = [
  NotificationSwitch(
    NotificationPrefs.pickupReminders,
    'Pickup reminders',
    '30 minutes before pickup opens and before it ends',
    Icons.alarm_outlined,
  ),
  NotificationSwitch(
    NotificationPrefs.itemChanges,
    'Item changes',
    'When an item you ordered changes',
    Icons.edit_note_outlined,
  ),
  NotificationSwitch(
    NotificationPrefs.favourites,
    'Favourites',
    'When a favourite is back on sale or in stock',
    Icons.favorite_border,
  ),
];

List<NotificationSwitch> notificationSwitchesFor(String role) =>
    role == 'vendor' ? _vendorSwitches : _customerSwitches;

const _switchDuration = Duration(milliseconds: 350);

// Fades the old content out and the new in while the box grows or shrinks to
// fit, such as when notifications are turned on and the settings appear.
// Each state's child needs its own key.
class NotificationStateSwitcher extends StatelessWidget {
  const NotificationStateSwitcher({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: _switchDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: _switchDuration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.passthrough,
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }
}

// The Notifications section on My Profile, laid out like Account Details. The
// pencil opens Notification Settings. While notifications are off on the
// phone, only the note to turn them on shows.
class NotificationSettingsSection extends StatefulWidget {
  const NotificationSettingsSection({
    super.key,
    required this.role,
    required this.onEdit,
    this.reloads = 0,
  });

  final String role;

  // Opens a page from My Profile, which shows its closing message.
  final Future<void> Function(String location) onEdit;

  // Goes up when My Profile reloads (Try Again or pull to refresh), so the
  // settings load again with it.
  final int reloads;

  @override
  State<NotificationSettingsSection> createState() =>
      _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState
    extends State<NotificationSettingsSection> {
  NotificationPrefs? _prefs;
  bool _failed = false;
  bool _askedAgain = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NotificationSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reloads != oldWidget.reloads) _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await context.read<NotificationRepository>().fetchPrefs();
      if (mounted) {
        setState(() {
          _prefs = prefs;
          _failed = false;
        });
      }
    } on ApiException {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _edit() async {
    await widget.onEdit(AppRoutes.profileNotificationsFor(widget.role));
    if (mounted) await _load();
  }

  Future<void> _turnOn(NotificationsController controller) async {
    if (_askedAgain) return controller.openSettings();
    final on = await controller.turnOn();
    if (mounted && !on) setState(() => _askedAgain = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<NotificationsController?>();
    final prefs = _prefs;
    final off = controller != null && !controller.permitted;

    return Container(
      key: const ValueKey('notification-settings'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Notifications',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              AnimatedSwitcher(
                duration: _switchDuration,
                child: off
                    ? const SizedBox(key: ValueKey('no-edit'), height: 48)
                    : IconButton(
                        key: const ValueKey('notification-settings-edit'),
                        tooltip: 'Edit notification settings',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: prefs == null ? null : _edit,
                      ),
              ),
            ],
          ),
          NotificationStateSwitcher(child: _body(off, controller, prefs)),
        ],
      ),
    );
  }

  Widget _body(
    bool off,
    NotificationsController? controller,
    NotificationPrefs? prefs,
  ) {
    final theme = Theme.of(context);
    return KeyedSubtree(
      key: ValueKey(
        off
            ? 'off'
            : _failed
            ? 'failed'
            : prefs == null
            ? 'loading'
            : 'on',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (off)
            Padding(
              padding: const EdgeInsets.only(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child: NotificationsOffNote(
                askedAgain: _askedAgain,
                onTurnOn: () => _turnOn(controller!),
              ),
            )
          // My Profile's own error box has the Try Again for this.
          else if (_failed)
            Padding(
              padding: const EdgeInsets.only(
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                "Couldn't load your notification settings.",
                key: const ValueKey('notification-settings-failed'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            )
          else if (prefs == null)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final item in notificationSwitchesFor(widget.role))
              _ValueRow(item: item, on: prefs.isOn(item.key)),
        ],
      ),
    );
  }
}

// The same row as Account Details: icon, small label, value.
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.item, required this.on});

  final NotificationSwitch item;
  final bool on;

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
          Icon(item.icon, size: 20, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                Text(
                  on ? 'On' : 'Off',
                  key: ValueKey('notification-value-${item.key}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Shown when notifications are turned off for SaveSpoon in Android. Once
// Android stops asking, the button opens the phone's Settings instead.
class NotificationsOffNote extends StatelessWidget {
  const NotificationsOffNote({
    super.key,
    required this.askedAgain,
    required this.onTurnOn,
  });

  final bool askedAgain;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('notifications-off'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.warningPale,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.notifications_off_outlined,
                  size: 18,
                  color: AppColors.onWarning,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  askedAgain
                      ? 'Notifications are still off. Open Settings and turn '
                            'on notifications for SaveSpoon.'
                      : 'Notifications are off for SaveSpoon on this phone. '
                            'You can still see them in the app.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.onWarning,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('notifications-turn-on'),
              onPressed: onTurnOn,
              child: Text(askedAgain ? 'Open Settings' : 'Turn On'),
            ),
          ),
        ],
      ),
    );
  }
}
