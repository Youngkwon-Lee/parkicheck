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

Xcode 26+ is required for Capacitor 8. Android Gradle build needs a JDK
and Android SDK; the original MacBook check found no usable Java runtime.
The platforms are developer projects, not signed or store-published binaries.

## Release gates

1. Manifest/icons and public-only service-worker cache verified.
2. Local static bundle and native camera permission settings verified.
3. iOS simulator app opens; this does not validate physical camera.
4. iPhone and Android real camera hand tracking, timing, capture, consent and
   repeated-result tests pass.
5. Hawk_I authenticated optional video uploads and result review separately verified.
6. Privacy/regulatory/store review; then TestFlight / Play internal testing.

Do not present REVIEW READY as clinical approval.

## First verified development check (2026-10-26)

- Source test suite: 47/47 passed after URL-query hardening.
- iOS: Xcode 27.1 simulator build succeeded; installed and launched in the
  iPhone Duo simulator, then simulator shut down (no persistent background run).
- Unverified: simulator UI rendering, physical camera tracking, repeated measure
  accuracy, consented Hawk_I server result, TestFlight signing and store review.
- Android: generated native project and copied static assets; Gradle SDK sync
  reported no usable Java runtime. APK/aab was not built.
- Production: no deploy, no existing patient records touched.
