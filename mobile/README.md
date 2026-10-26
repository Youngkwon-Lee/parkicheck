# ParkiCheck mobile app — developer preview

This is a native iOS and Android research prototype sharing ParkiCheck's existing
web assessment code. It is not a validated medical device, diagnostic application,
clinical UPDRS scoring tool, or medication-effect detector.

## Source and privacy boundaries

- Baseline: production commit 5fdd3f570c496be78b911c26f74da5c8272fcff9.
- Bundle identifier: kr.co.kinelo.parkicheck (provisional, confirm before app store release).
- Native app loads bundled local static resources, not a remote Vercel web URL.
- Network access is still needed for third-party MediaPipe/Supabase scripts,
  account access, and Hawk_I analysis. The PWA shell cache is not offline clinical analysis.
- The build copies only an explicit allowlist of public static files. It never includes
  environment files, patient records or video, access tokens, or device identifiers.
- Live camera requires OS permission. Server video upload requires separate consent
  and an authenticated account. No diagnosis or medication-effect inference is implied.

## PWA install after intentional web deployment

- iPhone Safari: open the ParkiCheck HTTPS address, Share > Add to Home Screen.
- Android Chrome: open the HTTPS address, choose Install app / Add to Home Screen.
- The existing production website does NOT get PWA features until this change is deployed.
- Verify research-only messaging and test camera on a physical phone, with consent.

## Native build

Node.js 22+ and Capacitor 8. Appropriate Xcode/Android tooling required.

    cd mobile
    npm ci
    npm test
    npx cap sync ios
    npx cap open ios

Android:

    cd mobile
    npm ci
    npm test
    npx cap sync android
    npx cap open android

Xcode 26+ is required for Capacitor 8. Android requires Android SDK 36 and
JDK 21. On the MacBook, Java 21 is installed outside the default shell PATH.
Use this process-scoped environment; do not change system Java:

    export JAVA_HOME=/opt/homebrew/opt/openjdk@21
    export PATH="$JAVA_HOME/bin:$PATH"
    export ANDROID_HOME="$HOME/Library/Android/sdk"
    cd mobile/android
    ./gradlew :app:assembleDebug --no-daemon --console=plain

The resulting Android APK is a debug build. iPhoneOS developer signing works,
but neither app has been signed for public distribution or store release.

## Release gates

1. Manifest/icons and public-only service-worker cache verified.
2. Local static bundle and native camera permission settings verified.
3. iOS simulator app opens; this does not validate physical camera.
4. iPhone and Android real camera hand tracking, timing, capture, consent and
   repeated-result tests pass.
5. Hawk_I authenticated optional video uploads and result review separately verified.
6. Privacy/regulatory/store review; then TestFlight / Play internal testing.

Do not present REVIEW READY as clinical approval.

## Latest device/build evidence (2026-10-26 KST)

Evidence source commit: 78ff183d2726b5197b568fdda8e3fd59140e5b42.
This documentation update does not modify runtime code.

- Existing and new static tests: 47/47 pass.
- Xcode 27.1: iPhoneOS Debug build signed using an existing Apple
  Development identity and wildcard development provisioning profile.
  The app was installed and launched on a paired iPhone 12 Pro running
  iOS 27.0.1 with Developer Mode enabled. No distribution signing.
- Physical iPhone app UI: unverified. A remote screenshot was black.
  Display-off/capture restriction vs. app rendering was not resolved.
  Process launch alone is not proof that camera or screen works.
- iOS Simulator: build, install and process launch succeeded. Screenshots
  showed startup/setup screens; proper ParkiCheck UI rendering was not
  confirmed in the simulator.
- Android: :app:assembleDebug BUILD SUCCESSFUL with OpenJDK 21 and
  Android SDK 36; 4.2 MB app-debug.apk created in
  mobile/android/app/build/outputs/apk/debug/ (ignored from Git).
  Package id is kr.co.kinelo.parkicheck, targetSdkVersion 36;
  APK Signature v2 verification passed. No Android phone connected.
- Production website unchanged. The PWA service worker is not live.
- No patient records, captured health videos, or third-party research
  data were used. PR #8 remains Draft and unmerged.

## Physical iPhone camera check still requiring user interaction

1. Unlock the paired iPhone 12 Pro and open ParkiCheck.
2. Confirm that the landing screen and research-only disclaimer appear.
   If black/blank, stop and record the symptom before camera access.
3. Select 로그인 없이 체험, then UPDRS 3.4 / FINGER TAPPING.
4. Keep optional Hawk_I video transfer OFF. Approve camera access only
   for a consenting volunteer; no patient or identifying data.
5. In good light, tap index finger and thumb for 10 seconds.
   Confirm moving hand landmarks, final observational metrics, and
   approximate agreement of tap count with a human reference.
6. Reopen the app and verify no unexpected raw-video upload or storage.
   Record pass/fail, not personally identifying images.

None of the physical camera checks above has been marked PASS.
Neither Apple App Store nor Google Play release is authorized.


## Camera switch update (2026-10-26)
- iPhone/Android app bundle now includes the same front/rear camera
  code as the production ParkiCheck web release, source
  2da48b8f76bd1c4995d11406843f31b30fe478d3.
- Rear switching needs a real phone with a physical rear camera;
  the iOS Simulator cannot validate it. WebKit camera retry and
  preview reattachment use no recording or image uploads.
- The physical iPhone was unavailable at the time of integration.
  A clean signed rebuild does not mean the installed device app
  has been upgraded. Do not claim physical rear-lens success until
  installation and an observed camera switch on the actual device.
