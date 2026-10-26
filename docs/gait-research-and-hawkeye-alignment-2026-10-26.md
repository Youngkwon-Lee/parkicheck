# ParkiCheck gait research integrity and HawkEye link

Date: 2026-10-26. Scope: non-production Draft PR.

## Defect

The old ParkiCheck live gait grade rounded a weighted combination:
cadence 45%, left/right step-count imbalance 25%, step interval CV
20%, arm displacement imbalance 10%. Badly tracked ankles can
drive a falsely high clinical-looking score. This is not a validated
MDS-UPDRS rating. The previous GAIT label said 3.9, but the official
Part III item is 3.10; 3.9 is arising from a chair. Old records are not
automatically reclassified.

## Research-only mitigation

New live gait shows measured step counts, cadence and tracking quality,
but no ordinal MDS-UPDRS grade. A minimal observation gate checks
at least 8 detected steps, 3 each side, and 4 seconds of tracking.
This is engineering completeness, not clinical accuracy. Unscored
gait metrics persist only in a research Activity Session with
GAIT_RESEARCH task code and never create an integer clinical-grade
Observation. The legacy history reader is unchanged.

With explicit video-recording consent, both finger and gait videos can
be staged in memory until Save and Analyze. A successful HawkEye server
result with a valid returned analysis ID unlocks an external result
dashboard link. A failed or unsubmitted job does not show that link.

## AI distinction

ParkiCheck local: MediaPipe Hands/Pose/FaceMesh + handcrafted motion
events and temporal metrics, not a trained clinical grade predictor.

HawkEye backend: video ROI/pose tracking, motion features and optional
model inference with declared method. Current health endpoint reports
a configured C0B VLM, but zero available CORAL task weights. Thus
requesting CORAL may fall back to rule scoring. Verify applied method
in the exact completed result, never infer from request arguments.

A publicly shared gait example, analysis ID
mixkit4855_public_stock_gait_1792542221_66b73a81a38a, reports
scoring_method=finetuned_vlm and model hawkeye-c0b-seed42. It does
not prove that a new ParkiCheck video completed the same inference.

## Release gates

- Clinician-reviewed labels, protocol, camera geometry and repeated
  gait tests needed before presenting a clinical rating.
- Real signed-in ParkiCheck upload -> HawkEye new analysis ID ->
  dashboard readback not yet validated.
- Raw video must not upload without explicit consent; test with
  public/consenting demo videos, not real patients.
- Prior historical classifications not modified.
- MDS-UPDRS software usage requires checking licensing permissions.

NINDS gait CDE:
https://pdbp.ninds.nih.gov/dictionary/publicData/dataElementAction!view.action?dataElementName=MDSUPDRSGaitScore

MDS permissions:
https://www.movementdisorders.org/MDS/MDS-Clinical-Outcome-Assessment/Permission-Request.htm

Related Face Fitness prototype:
https://github.com/Youngkwon-Lee/face-fitness

Not approved for production clinical grading or a release merge.
