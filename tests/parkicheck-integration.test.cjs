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

test('ParkiCheck stores patient-reported medication context with the assessment', () => {
  assert.match(html, /medication_context:\s*getMedicationContext\(new Date\(\)\)/);
  assert.match(html, /medication_context:\s*payload\.medication_context/);
  assert.match(html, /source:\s*'patient_reported_local'/);
});

test('saving waits for the consented Hawk I review to finish', () => {
  assert.match(html, /if \(hawkIReviewPromise\)[\s\S]*await hawkIReviewPromise/);
  assert.match(html, /if \(lastResultPayload\) void handleSaveResult\(\)/);
});
