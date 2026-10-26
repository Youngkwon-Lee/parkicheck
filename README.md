# ParkiCheck

ParkiCheck is the patient-facing assessment and medication-log surface for the
HawkEye Parkinson movement-research workflow.

## Production

- Patient app: <https://finger-tap-fx.vercel.app/>
- Clinician/research timeline: <https://hawkeye-labeling-tool.vercel.app/history>
- Hawk I new analysis: <https://hawkeye-labeling-tool.vercel.app/test>

Use the stable aliases above for team and user handoff. Deployment-specific
Vercel URLs are immutable review evidence, not permanent entry points.

## Product boundary

- ParkiCheck owns patient task execution, patient-reported medication events,
  and the canonical save contract for its assessment.
- Hawk I owns consented movement-video analysis and the deeper
  clinician/research review surface.
- Both services share an authenticated Supabase patient timeline. They do not
  infer medication effect, clinical ON/OFF state, treatment changes, or an
  autonomous diagnosis.
- A Hawk I review is an observational research aid. `REVIEW READY` means the
  result is available for human review; it does not mean clinical approval.

## Shared record contract

One ParkiCheck assessment uses one `assessment_session_id` across local metrics,
the optional Hawk I request, `activity_sessions`, and the matching observation.
`persistence_owner=parkicheck` prevents Hawk I from creating a duplicate
observation for the delegated request. Medication events are patient-reported
`medication_statements` and remain separate from score interpretation.

Do not store access tokens, person/session/observation identifiers, patient
media, or PHI in this repository or its documentation.

## Local verification

The application is static. Run its contract tests from the repository root:

```bash
node --test tests/*.test.cjs
```

The 2026-08-30 production release passed 41 tests. Browser readback confirmed
`REVIEW STATUS`, removed the misleading `VIDEO QUALITY` label, and verified the
copied/read-aloud status separator in `RESEARCH ENGINE · REVIEW READY`.

## Release

The linked Vercel project is `finger-tap-fx`. Git auto-deployment is not the
release path. Build locally and upload only the reviewed Build Output API
artifact:

```bash
vercel build --prod --yes --scope 22s-projects-de7c705f
vercel deploy --prebuilt --prod --yes --scope 22s-projects-de7c705f
```

Before deploying, confirm the Git worktree is clean, all tests pass, and the
linked `.vercel/project.json` names `finger-tap-fx`. If the project is paused,
resuming it is an explicit cost/operations decision; do not unpause it merely
to bypass a deployment error. After deployment, reload the stable alias and
verify HTTP 200, the expected review labels, and no new browser errors.

## Current release evidence

- Source: `codex/refine-hawk-review-copy-20260830@8a8ebe5`
- Production deployment: `dpl_JAokVfttdnm9ST6V2w9V6tdfRY2u`
- Stable URL: <https://finger-tap-fx.vercel.app/>

## Mobile application workstream (2026-10-26)

The optional PWA and Capacitor iOS/Android prototype live in the mobile/
directory. See mobile/README.md for install/build commands, privacy boundaries,
and outstanding physical-device verification.
