import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/load_error.dart';
import '../../../listings/presentation/widgets/icon_scale.dart';
import '../../data/notification_repository.dart';
import '../../domain/app_notification.dart';
import '../notification_links.dart';
import '../providers/notifications_controller.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.role, this.clock});

  final String role;
  final DateTime Function()? clock;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<AppNotification>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final inbox = await context.read<NotificationRepository>().fetchInbox();
      if (!mounted) return;
      context.read<NotificationsController?>()?.setUnreadCount(
        inbox.unreadCount,
      );
      setState(() {
        _items = inbox.items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _markAllRead() async {
    final now = DateTime.now();
    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<NotificationRepository>();
    final controller = context.read<NotificationsController?>();
    final before = _items!;
    setState(() => _items = [for (final item in before) item.markedRead(now)]);
    controller?.setUnreadCount(0);
    try {
      await repository.markAllRead();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _items = before);
      await controller?.refreshUnread();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _clear(AppNotification item) async {
    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<NotificationRepository>();
    final controller = context.read<NotificationsController?>();
    final before = _items!;
    setState(
      () => _items = [
        for (final other in before)
          if (other.id != item.id) other,
      ],
    );
    try {
      final unread = await repository.clear(item.id);
      controller?.setUnreadCount(unread);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _items = before);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _clearAll() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          "They'll be removed from your inbox. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('clear-all-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final repository = context.read<NotificationRepository>();
    final controller = context.read<NotificationsController?>();
    final before = _items!;
    setState(() => _items = const []);
    controller?.setUnreadCount(0);
    try {
      await repository.clearAll();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _items = before);
      await controller?.refreshUnread();
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _open(AppNotification item) async {
    if (!item.isRead) {
      final now = DateTime.now();
      setState(() {
        _items = [
          for (final other in _items!)
            other.id == item.id ? other.markedRead(now) : other,
        ];
      });
      final controller = context.read<NotificationsController?>();
      if (controller != null) {
        controller.setUnreadCount(
          controller.unreadCount > 0 ? controller.unreadCount - 1 : 0,
        );
      }
      try {
        await context.read<NotificationRepository>().markRead(item.id);
      } on ApiException {
        // Shown as read here; the server catches up on the next open.
      }
    }
    if (mounted) await openNotification(context, item.link, widget.role);
  }

  // Notification Settings closes with a message after a save.
  Future<void> _openSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = await context.push<String>(
      AppRoutes.profileNotificationsFor(widget.role),
    );
    if (saved != null) messenger.showSnackBar(SnackBar(content: Text(saved)));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.page,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          // Always there for Settings; the inbox actions join it once there
          // are notifications.
          PopupMenuButton<VoidCallback>(
            key: const ValueKey('inbox-menu'),
            tooltip: 'More options',
            iconSize: 24 * iconScale(context),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              if (items != null && items.any((item) => !item.isRead))
                PopupMenuItem(
                  key: const ValueKey('mark-all-read'),
                  value: _markAllRead,
                  child: const Text('Mark All as Read'),
                ),
              if (items != null && items.isNotEmpty)
                PopupMenuItem(
                  key: const ValueKey('clear-all'),
                  value: _clearAll,
                  child: const Text('Clear All'),
                ),
              PopupMenuItem(
                key: const ValueKey('inbox-settings'),
                value: _openSettings,
                child: const Text('Settings'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: switch ((items, _error)) {
          (null, final String error) => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              LoadError(
                title: "Couldn't load your notifications",
                message: error,
                onRetry: _load,
              ),
            ],
          ),
          (null, _) => const Center(child: CircularProgressIndicator()),
          (final List<AppNotification> list, _) when list.isEmpty => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: const [_EmptyInbox()],
          ),
          (final List<AppNotification> list, _) => ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: list.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: AppSpacing.md),
            // Swiping left clears one.
            itemBuilder: (context, index) => Dismissible(
              key: ValueKey('dismiss-${list[index].id}'),
              direction: DismissDirection.endToStart,
              background: const _ClearBackground(),
              onDismissed: (_) => _clear(list[index]),
              child: NotificationTile(
                item: list[index],
                now: (widget.clock ?? DateTime.now)(),
                onTap: () => _open(list[index]),
              ),
            ),
          ),
        },
      ),
    );
  }
}

class _ClearBackground extends StatelessWidget {
  const _ClearBackground();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.error,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, color: colors.onError),
              const SizedBox(width: AppSpacing.xs),
              Text('Clear', style: TextStyle(color: colors.onError)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xl),
        Icon(
          Icons.notifications_none,
          size: 48 * iconScale(context),
          color: AppColors.textMuted,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'No notifications yet',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Updates about your orders appear here for 30 days.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

IconData _iconFor(NotificationType type) => switch (type) {
  NotificationType.newOrder => Icons.receipt_long_outlined,
  NotificationType.orderCancelled => Icons.cancel_outlined,
  NotificationType.itemChanged => Icons.edit_note_outlined,
  NotificationType.pickupReminder => Icons.alarm_outlined,
  NotificationType.favouriteBack => Icons.favorite_border,
  NotificationType.stockLow => Icons.inventory_2_outlined,
  NotificationType.other => Icons.notifications_outlined,
};

// "Just now", "5 min ago", "Today, 5:00 PM", "Yesterday, 5:00 PM" or
// "18 Nov, 5:00 PM".
String notificationTimeLabel(
  BuildContext context,
  DateTime when,
  DateTime now,
) {
  final minutes = now.difference(when).inMinutes;
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return '$minutes min ago';
  final localizations = MaterialLocalizations.of(context);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(when));
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo == 0) return 'Today, $time';
  if (daysAgo == 1) return 'Yesterday, $time';
  return '${when.day} ${localizations.formatShortMonthDay(when).split(' ').first}, $time';
}

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.item,
    required this.now,
    required this.onTap,
  });

  final AppNotification item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scale = iconScale(context);
    final unread = !item.isRead;
    return InkWell(
      key: ValueKey('notification-${item.id}'),
      onTap: onTap,
      child: Container(
        color: unread ? AppColors.primaryPale : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + AppSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40 * scale,
              height: 40 * scale,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconFor(item.type),
                size: 22 * scale,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(item.body, style: textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    notificationTimeLabel(context, item.createdAt, now),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.sm,
                  top: AppSpacing.xs,
                ),
                child: Container(
                  key: const ValueKey('unread-dot'),
                  width: 10 * scale,
                  height: 10 * scale,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
