import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../domain/app_notification.dart';

// Where a notification leads for this role, or null when it leads nowhere.
String? notificationLocation(NotificationLink link, String role) {
  switch (link.type) {
    // Vendors can't view orders until vendor order management exists, so
    // these only mark the notification read for now.
    case NotificationType.newOrder:
    case NotificationType.orderCancelled:
      return null;
    case NotificationType.itemChanged:
    case NotificationType.pickupReminder:
      final orderId = link.orderId;
      return role == 'customer' && orderId != null
          ? AppRoutes.orderDetailsFor(orderId)
          : null;
    case NotificationType.stockLow:
      final listingId = link.listingId;
      return role == 'vendor' && listingId != null
          ? AppRoutes.vendorListingFor(listingId)
          : null;
    case NotificationType.favouriteBack:
      final listingId = link.listingId;
      return role == 'customer' && listingId != null
          ? AppRoutes.foodDetailsFor(listingId)
          : null;
    case NotificationType.other:
      return null;
  }
}

// Pages open on top, and a message they close with (such as "sold out") is
// shown.
Future<void> openNotification(
  BuildContext context,
  NotificationLink link,
  String role,
) async {
  final location = notificationLocation(link, role);
  if (location == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await context.push<Object?>(location);
  if (result is String && result.isNotEmpty) {
    messenger?.showSnackBar(SnackBar(content: Text(result)));
  }
}
