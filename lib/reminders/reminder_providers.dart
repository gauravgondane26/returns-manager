import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reminder_scheduler.dart';

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return ReminderScheduler();
});
