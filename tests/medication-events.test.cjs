const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildMedicationStatementRow,
  parseMedicationStatementRow,
  mergeMedicationLogs,
} = require('../medication-events.js');

const identity = {
  personId: '22222222-2222-4222-8222-222222222222',
  organizationId: '33333333-3333-4333-8333-333333333333',
};

test('builds a patient-reported completed medication statement', () => {
  const row = buildMedicationStatementRow({
    event_id: '11111111-1111-4111-8111-111111111111',
    medication: '레보도파',
    dose_mg: 125,
    taken_at: '2026-07-28T09:00:00Z',
  }, identity);

  assert.equal(row.fhir_id, 'parkicheck-medication-11111111-1111-4111-8111-111111111111');
  assert.equal(row.status, 'completed');
  assert.equal(row.medication_code, 'LEVODOPA');
  assert.equal(row.dosage.dose_mg, 125);
  assert.equal(row.dosage.app_source, 'parkicheck');
  assert.equal(row.information_source_type, 'patient');
  assert.equal(row.subject_person_id, identity.personId);
  assert.equal(row.organization_id, identity.organizationId);
  assert.equal(row.created_by, identity.personId);
});

test('parses a Supabase medication statement into the ParkiCheck log shape', () => {
  const log = parseMedicationStatementRow({
    id: '44444444-4444-4444-8444-444444444444',
    fhir_id: 'parkicheck-medication-11111111-1111-4111-8111-111111111111',
    medication_display: '레보도파',
    effective_start: '2026-07-28T09:00:00Z',
    dosage: { dose_mg: 125 },
  });

  assert.equal(log.event_id, '11111111-1111-4111-8111-111111111111');
  assert.equal(log.dose_mg, 125);
  assert.equal(log.sync_state, 'synced');
  assert.equal(log.source, 'supabase');
});

test('server copy wins when local fallback and Supabase share an event id', () => {
  const eventId = '11111111-1111-4111-8111-111111111111';
  const merged = mergeMedicationLogs(
    [{ event_id: eventId, medication: '레보도파', dose_mg: 125, taken_at: '2026-07-28T09:00:00Z', sync_state: 'pending' }],
    [{ event_id: eventId, medication: '레보도파', dose_mg: 125, taken_at: '2026-07-28T09:00:00Z', sync_state: 'synced', source: 'supabase' }],
  );

  assert.equal(merged.length, 1);
  assert.equal(merged[0].sync_state, 'synced');
  assert.equal(merged[0].source, 'supabase');
});
