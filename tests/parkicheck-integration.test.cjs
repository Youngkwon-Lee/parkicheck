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

test('ParkiCheck declares caller-owned persistence for the shared timeline', () => {
  assert.match(html, /assessment_session_id:\s*r\.measurement_context\?\.assessment_session_id/);
  assert.match(html, /hawk_i:\s*r\.measurement_context\?\.hawk_i/);
  assert.match(html, /hist-hawk-badge/);
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

test('video analysis stages a selected gait task for Hawk I review until save', () => {
  assert.match(html, /const videoTestType = testType === 'gait' \? 'gait' : 'finger';/);
  assert.match(html, /stageHawkIReview\(file, \{ testType: videoTestType \}\)/);
  assert.match(html, /testType: reviewTestType === 'gait' \? 'gait' : 'finger_tapping'/);
  assert.match(html, /function showVideoGaitResearchResult/);
  assert.match(html, /if \(videoTestType === 'gait'\) \{\s*showVideoGaitResearchResult\(file, duration\);/);
  assert.match(html, /local_scoring: 'not_available'/);
});

test('Hawk I review forwards the signed-in Supabase access token without storing it', () => {
  assert.match(html, /const \{ data: sessionData \} = await supa\.auth\.getSession\(\);/);
  assert.match(html, /const accessToken = sessionData\?\.session\?\.access_token \|\| null;/);
  assert.match(html, /accessToken,/);
});

test('Hawk I review reserves an authenticated in-progress activity session before video upload', () => {
  assert.match(html, /async function reserveHawkIActivitySession/);
  assert.match(html, /status: 'in_progress'/);
  assert.match(html, /from\('activity_sessions'\)[\s\S]*upsert\(sessionRow, \{ onConflict: 'id' \}\)/);
  assert.match(html, /await reserveHawkIActivitySession\(\{/);
  assert.match(html, /task_code: isGait \? 'UPDRS_3_9' : 'UPDRS_3_4'/);
});

test('login resets the prior identity context before opening the assessment', () => {
  assert.match(html, /const \{ data, error \} = await supa\.auth\.signInWithPassword/);
  assert.match(html, /function setAuthenticatedUser\(nextUser\)/);
  assert.match(html, /if \(previousUserId !== nextUserId\) \{\s*_personId = null;\s*_orgId = null;/);
  assert.match(html, /setAuthenticatedUser\(data\.user\);\s*updateAuthUI\(\);\s*trackAnalytics\('login_completed'/);
  assert.match(html, /supa\.auth\.onAuthStateChange\([\s\S]*setAuthenticatedUser\(session\?\.user \?\? null\)/);
});

test('Hawk I review creates an authenticated shared session before upload', () => {
  assert.match(html, /supa\.auth\.getSession\(\)[\s\S]*access_token/);
  assert.match(html, /async function reserveHawkIActivitySession/);
  assert.match(html, /await reserveHawkIActivitySession\(\{/);
  assert.match(html, /from\('activity_sessions'\)[\s\S]*upsert\(sessionRow, \{ onConflict: 'id' \}\)/);
  assert.match(html, /HawkIClient\.submitVideo\(file, \{[\s\S]*assessmentContext,[\s\S]*accessToken,/);
});

test('saving waits for the consented Hawk I review to finish', () => {
  assert.match(html, /if \(hawkIReviewPromise\)[\s\S]*await hawkIReviewPromise/);
  assert.match(html, /if \(lastResultPayload\) void handleSaveResult\(\)/);
});

test('a consented live finger-tapping session stages the raw camera stream until save', () => {
  assert.match(html, /id="liveHawkIConsent"/);
  assert.match(html, /게임 이펙트·화면 UI는 녹화되지 않으며/);
  assert.match(html, /이 브라우저에만 임시 보관합니다/);
  assert.match(html, /‘저장 후 HAWK_I 분석’을 눌렀을 때에만 Hawk_I 연구 서버로 전송합니다/);
  assert.match(html, /testType === 'finger' && document\.getElementById\('liveHawkIConsent'\)\?\.checked/);
  assert.match(html, /new MediaRecorder\(stream/);
  assert.match(html, /if \(liveHawkIRecordingEnabled\) hawkIReviewPromise = finishLiveHawkIRecording\(\)/);
  assert.match(html, /stageHawkIReview\(file\)/);
  assert.match(html, /if \(pendingHawkIReview && !lastHawkIResult\)[\s\S]*startHawkIReview\(pendingReview\.file, pendingReview\.options\)/);
  assert.match(html, /saveBtn\.textContent = pendingHawkIReview \? '💾 저장 후 HAWK_I 분석' : '💾 결과 저장';/);
  assert.match(html, /function discardStagedHawkIReview\(\)/);
  assert.match(html, /\$\('testRetryBtn'\)\.addEventListener\('click',\(\)=>\{\s*discardStagedHawkIReview\(\)/);
});

test('finger tapping makes near-contact feedback visible without changing the scoring threshold', () => {
  assert.match(html, /function drawFingerTapCharge\(landmarks, activeFingers, lx, ly\)/);
  assert.match(html, /const visualThreshold = 0\.145/);
  assert.match(html, /visual-only\. The clinical tap count still uses/);
  assert.match(html, /drawFingerTapCharge\(landmarks, activeFingers, lx, ly\)/);
  assert.match(html, /const isTap=dist<TAP_THRESH/);
});

test('finger tapping uses a balanced local cue for recordings', () => {
  assert.match(html, /const cueScale = Math\.min\(0\.58 \+ combo\*0\.035, 0\.9\)/);
  assert.match(html, /const particleCount = Math\.min\(10, 4 \+ Math\.floor\(combo \/ 2\)\)/);
  assert.match(html, /new Particle\(x,y,color,cueScale\*0\.55\)/);
  assert.match(html, /new Shockwave\(x,y,color,0,cueScale\)/);
  assert.match(html, /new GlowPulse\(x,y,color,cueScale\)/);
  assert.match(html, /if\(combo>=2\) effects\.push\(new RingSegment\(x,y,color,cueScale\*0\.8\)\)/);
  assert.match(html, /if\(combo>=4\) effects\.push\(new Burst\(x,y,color\)\)/);
  assert.doesNotMatch(html, /new ScreenFlash\(color\)/);
  assert.doesNotMatch(html, /new Lightning\(x,y,color\)/);
});

test('finger tapping presents observational metrics instead of a local ordinal grade', () => {
  assert.match(html, /id="resMedianITI"/);
  assert.match(html, /TAP INTERVAL \(MS\)/);
  assert.match(html, /RHYTHM CV \(%\)/);
  assert.match(html, /RELATIVE AMP \(%\)/);
  assert.match(html, /function setFingerRecordPresentation\(active\)/);
  assert.match(html, /node\.style\.display = active \? 'none' : '';/);
  assert.match(html, /finger-record-grid/);
  assert.match(html, /const isFingerRecord = testType === 'finger';/);
  assert.match(html, /FINGER TAPPING · RESEARCH LOG/);
  assert.match(html, /function fingerRecordFeedback\(n\)/);
  assert.match(html, /잘했어요! 수행 기록이 저장될 준비가 됐어요/);
});

test('every result gets a fresh canonical save contract and resets the save action', () => {
  assert.match(html, /assessment_session_id: payload\?\.assessment_session_id \|\| createAssessmentSessionId\(\)/);
  assert.match(html, /medication_context: payload\?\.medication_context \|\| getMedicationContext\(new Date\(\)\)/);
  assert.match(html, /saveBtn\.style\.display = '';/);
  assert.match(html, /currentAssessmentMedicationContext = getMedicationContext\(new Date\(\)\)/);
});

test('history renders an observational repeated medication comparison', () => {
  assert.match(html, /async function resolveHistoryPersonId/);
  assert.match(html, /개인 기록 연결 시간이 초과되었습니다/);
  assert.match(html, /from\('persons'\)[\s\S]*eq\('auth_user_id', currentUser\.id\)/);
  assert.match(html, /from\('organization_members'\)[\s\S]*eq\('person_id', existingPerson\.id\)/);
  assert.match(html, /\.in\('code', \['UPDRS_3_4', 'UPDRS_3_9'\]\)/);
  assert.match(html, /renderHistList\(\);\s*setTimeout\(refreshHistChart/);
  assert.match(html, /medication-comparison\.js/);
  assert.match(html, /id="medicationComparison"/);
  assert.match(html, /buildMedicationComparison\(histResults, activeHistFilter\)/);
  assert.match(html, /약효, 인과관계, 복약 변경 필요성을 의미하지 않습니다/);
});

test('ParkiCheck prefers the shared Hawk I workspace when the user is authorized', () => {
  assert.match(html, /HAWK_I_SHARED_ORGANIZATION_ID\s*=\s*'13d483d9-b785-41d4-8eb8-fc0b55d48c86'/);
  assert.match(html, /resolveHawkISharedOrganization/);
  assert.match(html, /from\('organization_members'\)[\s\S]*eq\('organization_id', HAWK_I_SHARED_ORGANIZATION_ID\)/);
  assert.match(html, /from\('org_clients'\)[\s\S]*eq\('organization_id', HAWK_I_SHARED_ORGANIZATION_ID\)/);
  assert.match(html, /_orgId\s*=\s*await resolveHawkISharedOrganization\(_personId\) \|\| rpc\.org_id/);
});

test('history and admin chart canvases do not block their controls', () => {
  assert.doesNotMatch(html, /(^|[}\s])canvas\s*\{\s*position\s*:\s*absolute/m);
  assert.match(html, /#canvas\s*\{\s*position\s*:\s*absolute/);
  assert.match(html, /#histChartCanvas\s*\{[^}]*display\s*:\s*block/);
  assert.match(html, /#profileBadge\s*\{[^}]*z-index\s*:\s*107/);
  assert.match(html, /#historyOverlay\s*\{[^}]*z-index\s*:\s*108/);
  assert.match(html, /#adminOverlay\s*\{[^}]*z-index\s*:\s*109/);
});
