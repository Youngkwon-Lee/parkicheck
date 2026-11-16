# ParkiCheck iOS (self-recording app)

Native SwiftUI app for recording finger tapping and medication intake on-device.
It reports descriptive measurements only: no score, severity grade, diagnosis,
or medication-effect inference. Camera frames are processed in memory with
Apple Vision and are never stored or transmitted. Records live in SwiftData on
the device and can be exported (CSV) or deleted by the user.

## Build

`project.yml` is the source of truth; the `.xcodeproj` is generated and ignored.

```bash
cd ios
xcodegen generate
xcodebuild test -project ParkiCheck.xcodeproj -scheme ParkiCheck \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The simulator has no front camera, so the tapping screen shows "카메라를 사용할 수 없습니다".
Hand tracking must be checked on a real iPhone.

## Layout

- `Tapping/` — `TapDetector` (thumb–index closure with hysteresis, normalized by hand size) and
  `TapMetrics` (count, rate, median interval, interval CV, trimmed mean opening, second-half
  decrement, pauses ≥ 0.6 s). Ported from the web app's finger-tapping logic; covered by unit tests.
- `Camera/` — `HandTracker` (AVFoundation + `VNDetectHumanHandPoseRequest`) and the preview/overlay.
- `Models/` — SwiftData `TapSession`, `MedicationEntry`.
- `Views/` — tabs: 기록, 추이, 복약, 설정 (export, delete all), first-launch notice.

## Before App Store / TestFlight submission

- [ ] Set `AppConfig.privacyPolicyURL` to a published privacy policy.
- [ ] Set the bundle identifier and signing team in `project.yml`.
- [ ] Add an app icon (`Assets.xcassets`).
- [ ] App Privacy label: "Data Not Collected" holds only while everything stays on-device.
- [ ] Keep store copy free of "UPDRS", "진단", "점수", and "AI 평가"; describe the app as a self-recording tool.
- [ ] Verify hand tracking and tap counts on a real device against the web app.
- [ ] Adding accounts or a server sync later requires in-app account deletion and a privacy label update.
