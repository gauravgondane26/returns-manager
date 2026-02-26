import 'item_enums.dart';

class DeadlineEngine {
  static const int minReturnWindowDays = 1;
  static const int maxReturnWindowDays = 120;
  static const int defaultWindowDays = 30;
  static const int sheinWindowDays = 35;

  static int defaultWindowForStore(StoreType store) {
    if (store == StoreType.shein) {
      return sheinWindowDays;
    }
    return defaultWindowDays;
  }

  static int clampReturnWindowDays(int days) {
    if (days < minReturnWindowDays) {
      return minReturnWindowDays;
    }
    if (days > maxReturnWindowDays) {
      return maxReturnWindowDays;
    }
    return days;
  }

  static DateTime atStartOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static DateTime calculateReturnDeadline({
    required DateTime deliveredAt,
    required int returnWindowDays,
  }) {
    final deliveredDay = atStartOfDay(deliveredAt);
    final clampedDays = clampReturnWindowDays(returnWindowDays);
    return deliveredDay.add(Duration(days: clampedDays - 1));
  }

  static int calculateReturnWindowDays({
    required DateTime deliveredAt,
    required DateTime returnDeadline,
  }) {
    final deliveredDay = atStartOfDay(deliveredAt);
    final deadlineDay = atStartOfDay(returnDeadline);
    final days = deadlineDay.difference(deliveredDay).inDays + 1;
    return clampReturnWindowDays(days);
  }

  static int daysRemaining({
    required DateTime returnDeadline,
    DateTime? now,
  }) {
    final today = atStartOfDay(now ?? DateTime.now());
    final deadlineDay = atStartOfDay(returnDeadline);
    return deadlineDay.difference(today).inDays;
  }

  static ItemStatus resolveStatus({
    required ItemStatus status,
    required DateTime returnDeadline,
    DateTime? now,
  }) {
    final remaining = daysRemaining(returnDeadline: returnDeadline, now: now);

    if (status == ItemStatus.pending && remaining < 0) {
      return ItemStatus.expired;
    }
    if (status == ItemStatus.expired && remaining >= 0) {
      return ItemStatus.pending;
    }
    return status;
  }

  static bool isInReturnPeriod({
    required ItemStatus status,
    required DateTime returnDeadline,
    DateTime? now,
  }) {
    return resolveStatus(status: status, returnDeadline: returnDeadline, now: now) ==
        ItemStatus.pending;
  }
}
