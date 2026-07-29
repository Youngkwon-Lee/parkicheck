const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const videoDetectorSource = html.slice(
  html.indexOf('function detectTapsVideo'),
  html.indexOf('// TAP DETECTION (live camera)'),
);

test('ParkiCheck persists one assessment session across local and Hawk I results', () => {
  assert.match(html, /assessment-session\.js/);
  assert.match(html, /from\('activity_sessions'\)[\s\S]*upsert\(sessionRow, \{ onConflict: 'id' \}\)/);
  assert.match(html, /from\('observations'\)[\s\S]*upsert\(observationRow, \{ onConflict: 'fhir_id' \}\)/);
  assert.match(html, /buildObservationRow\([\s\S]*payload,[\s\S]*identity,[\s\S]*sessionRow\.id/);
  assert.match(html, /assessmentSessionId,\s*patientId,/s);
  assert.match(html, /assessmentContext,/);
  assert.match(html, /buildAssessmentContext\([\s\S]*assessmentPayload,[\s\S]*identity/);
  assert.match(html, /patientId = `research-\$\{assessmentSessionId\}`/);
  assert.match(html, /lastResultPayload\.hawk_i = normalizedHawkIResult/);
});

test('ParkiCheck can split direct video upload from same-origin result polling', () => {
  assert.match(html, /get\('hawk_i_upload_base'\)/);
  assert.match(html, /resolveAllowedUploadBaseUrl\(uploadCandidate\)/);
  assert.match(html, /uploadBaseUrl/);
});

test('ParkiCheck stores patient-reported medication context with the assessment', () => {
  assert.match(html, /medication_context: payload\?\.medication_context \|\| getMedicationContext\(new Date\(\)\)/);
  assert.match(html, /currentAssessmentMedicationContext \|\| getMedicationContext\(new Date\(\)\)/);
  assert.match(html, /medication_context:\s*payload\.medication_context/);
  assert.match(html, /source:\s*'patient_reported_local'/);
  assert.match(html, /medicationContext,/);
  assert.match(html, /영상과 환자 보고 복약 시점 정보를/);
});

test('medication logs use the authenticated Supabase timeline with local fallback', () => {
  assert.match(html, /medication-events\.js/);
  assert.match(html, /from\('medication_statements'\)[\s\S]*insert\(row\)/);
  assert.match(html, /like\('fhir_id', 'parkicheck-medication-%'\)/);
  assert.match(html, /mergeMedicationLogs\(getLocalMedLogs\(\), serverMedicationLogs\)/);
  assert.match(html, /서버 저장 실패 · 기록은 이 기기에 보관되었습니다/);
});

test('video analysis resets stale assessment selection to finger tapping', () => {
  assert.match(html, /async function analyzeVideoFile\(file\) \{\s*testType = 'finger';/);
});

test('video analysis counts index-thumb cycles from only one primary hand', () => {
  assert.match(html, /video-tap-detector\.js/);
  assert.match(html, /const primaryHand = handResults\.multiHandLandmarks\[0\]/);
  assert.match(html, /const tip=landmarks\[FINGER_TIPS\[fi\]\]/);
  assert.match(html, /videoIndexTapDetector\.observe\(dist,timestampMs\)/);
  assert.doesNotMatch(videoDetectorSource, /FINGER_TIPS\.forEach/);
});

test('assessment selector exposes the video-analysis route above its blocking overlay', () => {
  assert.match(html, /id="selectorVideoBtn"[\s\S]*onclick="setMode\('video'\)"/);
});

test('login applies the authenticated user before opening the assessment', () => {
  assert.match(html, /const \{ data, error \} = await supa\.auth\.signInWithPassword/);
  assert.match(html, /currentUser = data\.user;\s*updateAuthUI\(\);\s*trackAnalytics\('login_completed'/);
});

test('Hawk I review creates an authenticated shared session before upload', () => {
  assert.match(html, /supa\.auth\.getSession\(\)[\s\S]*access_token/);
  assert.match(
    html,
    /buildActivitySessionRow\([\s\S]*\{ status: 'in_progress' \}[\s\S]*from\('activity_sessions'\)[\s\S]*upsert\(sessionRow, \{ onConflict: 'id' \}\)[\s\S]*HawkIClient\.submitVideo/,
  );
  assert.match(html, /HawkIClient\.submitVideo\(file, \{[\s\S]*assessmentContext,[\s\S]*accessToken,/);
});

test('saving waits for the consented Hawk I review to finish', () => {
  assert.match(html, /if \(hawkIReviewPromise\)[\s\S]*await hawkIReviewPromise/);
  assert.match(html, /if \(lastResultPayload\) void handleSaveResult\(\)/);
});

test('every result gets a fresh canonical save contract and resets the save action', () => {
  assert.match(html, /assessment_session_id: payload\?\.assessment_session_id \|\| createAssessmentSessionId\(\)/);
  assert.match(html, /medication_context: payload\?\.medication_context \|\| getMedicationContext\(new Date\(\)\)/);
  assert.match(html, /saveBtn\.style\.display = '';/);
  assert.match(html, /currentAssessmentMedicationContext = getMedicationContext\(new Date\(\)\)/);
});

test('history renders an observational repeated medication comparison', () => {
  assert.match(html, /medication-comparison\.js/);
  assert.match(html, /id="medicationComparison"/);
  assert.match(html, /buildMedicationComparison\(histResults, activeHistFilter\)/);
  assert.match(html, /약효, 인과관계, 복약 변경 필요성을 의미하지 않습니다/);
});

test('history and admin chart canvases do not block their controls', () => {
  assert.doesNotMatch(html, /(^|[}\s])canvas\s*\{\s*position\s*:\s*absolute/m);
  assert.match(html, /#canvas\s*\{\s*position\s*:\s*absolute/);
  assert.match(html, /#histChartCanvas\s*\{[^}]*display\s*:\s*block/);
  assert.match(html, /#profileBadge\s*\{[^}]*z-index\s*:\s*107/);
  assert.match(html, /#historyOverlay\s*\{[^}]*z-index\s*:\s*108/);
  assert.match(html, /#adminOverlay\s*\{[^}]*z-index\s*:\s*109/);
});
