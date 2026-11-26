import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../notification_links.dart';
import '../providers/notifications_controller.dart';

// Opens a tapped notification once the tab shell is showing, so the login
// and splash screens can't send the user elsewhere afterwards. Also asks for
// the notification permission once per phone, on the first Home after login.
class NotificationLinkOpener extends StatefulWidget {
  const NotificationLinkOpener({
    super.key,
    required this.role,
    required this.child,
  });

  final String role;
  final Widget child;

  @override
  State<NotificationLinkOpener> createState() => _NotificationLinkOpenerState();
}

class _NotificationLinkOpenerState extends State<NotificationLinkOpener> {
  NotificationsController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<NotificationsController?>();
    if (controller == _controller) return;
    _controller?.removeListener(_openPending);
    _controller = controller?..addListener(_openPending);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openPending();
      if (mounted) controller?.askOnce();
    });
  }

  void _openPending() {
    final controller = _controller;
    if (!mounted || controller?.pendingLink == null) return;
    if (controller!.role != widget.role) return;
    final link = controller.takePendingLink()!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openNotification(context, link, widget.role);
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_openPending);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
