# Returns Manager

Flutter app for tracking return windows, Gmail delivery ingestion, reminders,
calendar export, and offline-first Firestore sync.

## Local Development

```bash
flutter pub get
flutter run -d <device-id>
```

## Validation

```bash
flutter analyze
flutter test
```

## Docs
- `docs/quality/performance_checks.md`
- `docs/release/testflight_release_path.md`

## Firebase
- Firestore rules are in `firestore.rules`.
- After changing rules, deploy with:
  ```bash
  firebase deploy --only firestore:rules
  ```
