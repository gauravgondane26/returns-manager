import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_export_service.dart';

final calendarExportServiceProvider = Provider<CalendarExportService>((ref) {
  return CalendarExportService();
});
