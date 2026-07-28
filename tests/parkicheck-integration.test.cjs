const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

test('ParkiCheck persists one assessment session across local and Hawk I results', () => {
  assert.match(html, /assessment-session\.js/);
  assert.match(html, /from\('activity_sessions'\)[\s\S]*upsert\(sessionRow, \{ onConflict: 'id' \}\)/);
  assert.match(html, /from\('observations'\)[\s\S]*upsert\(observationRow, \{ onConflict: 'fhir_id' \}\)/);
  assert.match(html, /buildObservationRow\([\s\S]*payload,[\s\S]*identity,[\s\S]*sessionRow\.id/);
  assert.match(html, /assessmentSessionId,\s*patientId,/s);
  assert.match(html, /assessmentContext,/);
  assert.match(html, /buildAssessmentContext\(\{/);
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

test('video analysis resets stale assessment selection to finger tapping', () => {
  assert.match(html, /async function analyzeVideoFile\(file\) \{\s*testType = 'finger';/);
});

test('login applies the authenticated user before opening the assessment', () => {
  assert.match(html, /const \{ data, error \} = await supa\.auth\.signInWithPassword/);
  assert.match(html, /currentUser = data\.user;\s*updateAuthUI\(\);\s*trackAnalytics\('login_completed'/);
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
