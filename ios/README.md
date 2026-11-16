# ParkiCheck iOS

Native SwiftUI app for Parkinson's self-recording: medication intake, patient-reported state,
symptoms and movement tasks. Positioned as a recording tool, not an assessment: no score,
severity grade, scale item number, diagnosis, or medication-effect inference appears in the app.
Everything stays on the device (SwiftData); camera frames and speech are processed in memory.

## Build

`project.yml` is the source of truth; the `.xcodeproj` is generated and ignored.

```bash
cd ios
xcodegen generate
xcodebuild test -project ParkiCheck.xcodeproj -scheme ParkiCheck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The simulator has no camera or microphone input, so tasks and speech must be checked on a real iPhone.

## Structure

- `Agent/` — on-device home coach. `IntentParser` turns typed or spoken Korean into intents
  (intake with times like "2시에", state, symptoms incl. falls, commands, notes); `ParkiAgent`
  records them and returns cards; `SpeechInput` is on-device Korean speech-to-text when supported.
  No LLM and no network.
- `App/` — app shell, floating tab bar (홈 · 검사 · 기록 · 마이), `NotificationManager`
  (daily dose reminders with "먹었어요" / snooze actions, a state check one hour after each dose).
- `Tasks/` — ten movement tasks and their analyzers (finger tapping, fist open/close, palm flips,
  rest and postural tremor, toe tapping, knee lifts, standing posture, gait, face/blinks).
  Ported from the web app with fixes: one sample per camera frame, peak amplitudes instead of
  threshold constants, hand-size/segment normalization, windowed + detrended tremor spectrum
  with a clarity check, one tracked hand.
- `Camera/` — `MotionTracker` (Apple Vision hand/body/face on the front camera, unmirrored analysis).
- `Models/` — SwiftData records and the dose-schedule / weekly-summary logic.
- `Views/` — chat home, checks and daily check flow, records with weekly summary and a printable
  clinician PDF, medication editor with a Parkinson's drug list, settings.
- `Design/CoachStyle.swift` — light theme from the Kinelo client app palette
  (physio_app `client-theme.ts`) with Kinelo Coach components; sizes raised for older users.

## Unvalidated constants (tune on device)

Toe-tap lift 0.12 (shank), knee lift 0.25 (thigh), gait step lift 0.08, palm-flip deadband 0.08,
tremor clarity 10× median, blink 55%/75% of baseline eye openness.

## Before App Store / TestFlight submission

- [ ] Set `AppConfig.privacyPolicyURL`, bundle identifier, signing team, app icon.
- [ ] App Privacy label "Data Not Collected" holds only while everything stays on-device.
- [ ] Verify the medication list names against current Korean prescriptions.
- [ ] Keep store copy free of scale names, "진단", "점수" and "AI 평가".
