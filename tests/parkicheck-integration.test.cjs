const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

test('ParkiCheck persists one assessment session across local and Hawk I results', () => {
  assert.match(html, /assessment_session_id:\s*payload\.assessment_session_id/);
  assert.match(html, /assessmentSessionId,\s*patientId,/s);
  assert.match(html, /patientId = `research-\$\{assessmentSessionId\}`/);
  assert.match(html, /lastResultPayload\.hawk_i = normalizedHawkIResult/);
});

test('ParkiCheck can split direct video upload from same-origin result polling', () => {
  assert.match(html, /get\('hawk_i_upload_base'\)/);
  assert.match(html, /resolveAllowedUploadBaseUrl\(uploadCandidate\)/);
  assert.match(html, /uploadBaseUrl/);
});

test('ParkiCheck stores patient-reported medication context with the assessment', () => {
  assert.match(html, /medication_context:\s*getMedicationContext\(new Date\(\)\)/);
  assert.match(html, /medication_context:\s*payload\.medication_context/);
  assert.match(html, /source:\s*'patient_reported_local'/);
  assert.match(html, /medicationContext:\s*getMedicationContext\(new Date\(\)\)/);
  assert.match(html, /영상과 환자 보고 복약 시점 정보를/);
});

test('saving waits for the consented Hawk I review to finish', () => {
  assert.match(html, /if \(hawkIReviewPromise\)[\s\S]*await hawkIReviewPromise/);
  assert.match(html, /if \(lastResultPayload\) void handleSaveResult\(\)/);
});

test('history renders an observational repeated medication comparison', () => {
  assert.match(html, /medication-comparison\.js/);
  assert.match(html, /id="medicationComparison"/);
  assert.match(html, /buildMedicationComparison\(histResults, activeHistFilter\)/);
  assert.match(html, /약효, 인과관계, 복약 변경 필요성을 의미하지 않습니다/);
});
