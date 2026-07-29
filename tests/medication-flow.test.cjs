const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const migration = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'migrations', '20260729022500_allow_patient_reported_medication_insert.sql'),
  'utf8',
);

test('medication form preserves decimal doses and exposes accessible names', () => {
  assert.match(html, /id="medDose"[^>]*step="0\.001"[^>]*aria-label="복용량 밀리그램"/);
  assert.match(html, /const dose = rawDose === '' \? null : Number\(rawDose\)/);
  assert.doesNotMatch(html, /parseInt\(document\.getElementById\('medDose'\)\.value\)/);
  assert.match(html, /id="medName"[^>]*aria-label="복용 약물"/);
  assert.match(html, /id="medTime"[^>]*aria-label="복용 시각"/);
  assert.match(html, /id="medSyncStatus" role="status" aria-live="polite"/);
});

test('history tabs communicate their selected state', () => {
  assert.match(html, /role="tablist" aria-label="내 기록 보기 방식"/);
  assert.match(html, /id="htChart" role="tab" aria-selected="true"/);
  assert.match(html, /setAttribute\('aria-selected', String\(chartActive\)\)/);
});

test('patient-reported medication insert policy is tightly scoped to the signed-in person', () => {
  assert.match(migration, /for insert\s+to authenticated/i);
  assert.match(migration, /subject_person_id = \(select public\.get_my_person_id\(\)\)/);
  assert.match(migration, /created_by = \(select public\.get_my_person_id\(\)\)/);
  assert.match(migration, /information_source_type = 'patient'/);
  assert.match(migration, /medication_code_system = 'urn:parkicheck:patient-reported'/);
  assert.match(migration, /om\.organization_id = medication_statements\.organization_id/);
  assert.match(migration, /om\.status = 'active'/);
});
