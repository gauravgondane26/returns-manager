# Performance Checks

Use this checklist before beta cut.

## Baseline commands
```bash
flutter analyze
flutter test
flutter run --profile -d <device-id>
```

## App-level checks
- Cold start to Home tab should feel responsive (< 3s on emulator, faster on device).
- Tab switching should not jank.
- Gmail sync should show completion summary and not freeze UI.
- Calendar tab month navigation should remain smooth.
- Editing and saving item should not block UI for long operations.

## Data checks
- Repeated Gmail sync should upsert and not duplicate entries.
- Large list behavior: test with at least 100 items and verify scroll smoothness.
- Offline edit/online reconcile should converge to last write.

## Notification checks
- Verify reminder scheduling at 7/3/1 days.
- Verify reminders are canceled after status changes to Keep/Return.
- Verify same-day fallback behavior when scheduling occurs after reminder hour.

## Logging guidance
- Keep user-facing errors concise.
- Parse miss telemetry should populate `users/{uid}/telemetry/*`.
- Avoid storing full raw email data; use redacted samples only.
