abstract final class PickupTimes {
  static const Duration _defaultLength = Duration(hours: 2);
  static const int _stepMinutes = 30;
  static const int _minutesInDay = 24 * 60;

  static DateTime _toMinute(DateTime time) =>
      DateTime(time.year, time.month, time.day, time.hour, time.minute);

  static DateTime defaultStart(DateTime now) {
    final exact = now.second == 0 && now.millisecond == 0;
    final minutes = now.hour * 60 + now.minute + (exact ? 0 : 1);
    final rounded = (minutes / _stepMinutes).ceil() * _stepMinutes;
    if (rounded >= _minutesInDay) return _toMinute(now);
    return DateTime(now.year, now.month, now.day, 0, rounded);
  }

  static DateTime defaultEnd(DateTime start) {
    final end = start.add(_defaultLength);
    final lastMinute = DateTime(start.year, start.month, start.day, 23, 59);
    return end.isAfter(lastMinute) ? lastMinute : end;
  }

  static String? startError(DateTime start, DateTime now) =>
      start.isBefore(_toMinute(now))
      ? "That time has passed. Choose a time that hasn't passed yet."
      : null;

  static String? endError(DateTime end, DateTime start, DateTime now) {
    if (!end.isAfter(start)) return 'Pickup must end after it starts.';
    if (!end.isAfter(now)) return 'Pickup must end later today.';
    return null;
  }
}
