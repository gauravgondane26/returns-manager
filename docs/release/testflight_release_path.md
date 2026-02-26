# TestFlight Release Path

This is the current iPhone beta release path for Returns Manager.

## 1. Prerequisites
- Apple Developer account with App Store Connect access.
- Physical iPhone for final sign-in and notification verification.
- Xcode installed on macOS with the latest iOS SDK.
- Firebase iOS app registered and `GoogleService-Info.plist` added to `ios/Runner/`.

## 2. App Store Connect Setup
1. Create app entry in App Store Connect.
2. Bundle ID must match `ios/Runner.xcodeproj` product bundle identifier.
3. Set version/build strategy (for example: `1.0.0`, build `1` then increment build each upload).
4. Configure required privacy fields and support URL.

## 3. iOS Build Config
1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select `Runner` target and set Team + Signing (Automatic recommended).
3. Ensure Push Notifications + Background Modes are enabled if reminders are used.
4. Confirm Google Sign-In URL schemes exist in `ios/Runner/Info.plist`.

## 4. Build + Upload
1. From repo root:
   ```bash
   flutter clean
   flutter pub get
   flutter build ipa --release
   ```
2. Upload IPA using either:
   - Xcode Organizer (`Distribute App`), or
   - Transporter app.

## 5. TestFlight Enablement
1. Wait for processing in App Store Connect.
2. Add internal testers first.
3. Verify smoke flows on device:
   - Google sign-in/out
   - Manual CRUD
   - Gmail sync button behavior
   - Reminders (1-day test)
   - Calendar export create/update/remove

## 6. Release Checklist
- Firestore rules deployed for items + telemetry.
- Crash-free launch on clean install.
- No blocker issues in `flutter analyze` or `flutter test`.
- Build number incremented before every upload.
