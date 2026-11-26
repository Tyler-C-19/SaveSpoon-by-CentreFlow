import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/widgets/auto_refresh.dart';
import '../../../listings/presentation/widgets/icon_scale.dart';
import '../providers/notifications_controller.dart';

// The header bell, with the number of unread notifications. It wiggles when a
// new one comes in.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, required this.role});

  final String role;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin, AutoRefresh {
  late final AnimationController _wiggle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  // In turns, swinging less each time.
  late final Animation<double> _swing = TweenSequence<double>([
    for (final (from, to) in const [
      (0.0, 0.05),
      (0.05, -0.05),
      (-0.05, 0.035),
      (0.035, -0.02),
      (-0.02, 0.0),
    ])
      TweenSequenceItem(
        tween: Tween(begin: from, end: to),
        weight: 1,
      ),
  ]).animate(_wiggle);
  int? _count;

  // Types switched off send no push, so the count is also checked on a timer.
  @override
  Future<void> autoRefresh() async =>
      context.read<NotificationsController?>()?.refreshUnread();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final count = context.watch<NotificationsController?>()?.unreadCount ?? 0;
    final last = _count;
    _count = count;
    if (last != null &&
        count > last &&
        !MediaQuery.disableAnimationsOf(context)) {
      _wiggle.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _wiggle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationsController?>();
    if (controller == null) return const SizedBox.shrink();
    final count = controller.unreadCount;
    final label = count > 99 ? '99+' : '$count';
    return IconButton(
      key: const ValueKey('notification-bell'),
      tooltip: count == 0 ? 'Notifications' : 'Notifications, $count unread',
      iconSize: 24 * iconScale(context),
      onPressed: () async {
        await context.push<void>(AppRoutes.notificationsFor(widget.role));
        await controller.refreshUnread();
      },
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(label),
        child: RotationTransition(
          key: const ValueKey('bell-wiggle'),
          turns: _swing,
          alignment: Alignment.topCenter,
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
    );
  }
}
