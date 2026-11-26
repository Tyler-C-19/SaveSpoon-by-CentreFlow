import 'package:flutter/material.dart';

import '../../orders/domain/order.dart';

// The same lead time the server uses to add reminders to the inbox.
const Duration reminderLead = Duration(minutes: 30);

class PickupReminder {
  const PickupReminder({
    required this.id,
    required this.orderId,
    required this.at,
    required this.title,
    required this.body,
  });

  final int id;
  final String orderId;
  final DateTime at;
  final String title;
  final String body;
}

// A stable number for each reminder, since the phone identifies reminders by
// number.
int reminderIdFor(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

String _time(DateTime value) => const DefaultMaterialLocalizations()
    .formatTimeOfDay(TimeOfDay.fromDateTime(value.toLocal()));

// "5:00–6:00 PM", or "11:30 AM–12:30 PM" when the halves of the day differ.
String pickupWindowLabel(DateTime start, DateTime end) {
  final from = _time(start).split(' ');
  final to = _time(end);
  return from.length == 2 && from[1] == to.split(' ').last
      ? '${from[0]}–$to'
      : '${_time(start)}–$to';
}

String _place(Order order) {
  final address = order.pickupAddress;
  return address == null || address.isEmpty
      ? order.stallName
      : '${order.stallName}, $address';
}

String opensBody(Order order) =>
    '${order.quantity} x ${order.itemName} at ${_place(order)}. '
    '${pickupWindowLabel(order.pickupStart, order.pickupEnd)}.';

String endsBody(Order order) =>
    "Don't forget to collect ${order.quantity} x ${order.itemName} at "
    '${order.stallName} before ${_time(order.pickupEnd)}.';

// Each open order is reminded 30 minutes before pickup opens and 30 minutes
// before it ends, when that time is still ahead and the order was placed
// before it. The closing one only when pickup lasts longer than 30 minutes.
List<PickupReminder> planReminders(Iterable<Order> orders, DateTime now) {
  final reminders = <PickupReminder>[];
  for (final order in orders) {
    if (!order.isOpen || !order.pickupEnd.isAfter(now)) continue;
    final created = order.createdAt;
    bool due(DateTime at) =>
        at.isAfter(now) && (created == null || !created.isAfter(at));

    final opens = order.pickupStart.subtract(reminderLead);
    if (due(opens)) {
      reminders.add(
        PickupReminder(
          id: reminderIdFor(order.id),
          orderId: order.id,
          at: opens,
          title: 'Pickup opens in 30 minutes',
          body: opensBody(order),
        ),
      );
    }
    final ends = order.pickupEnd.subtract(reminderLead);
    if (ends.isAfter(order.pickupStart) && due(ends)) {
      reminders.add(
        PickupReminder(
          id: reminderIdFor('${order.id}:end'),
          orderId: order.id,
          at: ends,
          title: 'Pickup ends in 30 minutes',
          body: endsBody(order),
        ),
      );
    }
  }
  return reminders;
}
