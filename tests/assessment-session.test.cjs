const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildActivitySessionRow,
  buildObservationRow,
} = require('../assessment-session.js');

const payload = {
  assessment_session_id: '11111111-1111-4111-8111-111111111111',
  medication_context: {
    available: true,
    medication: '레보도파',
    dose_mg: 100,
    taken_at: '2026-07-27T00:00:00.000Z',
    assessment_at: '2026-07-27T01:30:00.000Z',
    hours_before_assessment: 1.5,
  },
  hawk_i: { analysis_id: 'hawk-123', score: 2, method: 'coral' },
  score: 1,
  raw_score: 1.2,
  frequency: 3.5,
  fatigability: 8,
  confidence: 'HIGH',
  mode: 'video',
  n_taps: 35,
  duration_sec: 10,
  factors: { test_type: 'finger' },
};

const identity = {
  personId: '22222222-2222-4222-8222-222222222222',
  organizationId: '33333333-3333-4333-8333-333333333333',
  createdBy: '22222222-2222-4222-8222-222222222222',
};

test('ParkiCheck uses one canonical activity session for local and Hawk I data', () => {
  const session = buildActivitySessionRow(payload, identity);
  const observation = buildObservationRow(payload, identity, session.id);

  assert.equal(session.id, payload.assessment_session_id);
  assert.equal(session.subject_person_id, identity.personId);
  assert.equal(session.metrics.assessment_session_id, payload.assessment_session_id);
  assert.equal(session.metrics.hawk_i.analysis_id, 'hawk-123');
  assert.equal(observation.activity_session_id, session.id);
  assert.equal(observation.subject_person_id, identity.personId);
  assert.equal(observation.measurement_context.assessment_session_id, session.id);
  assert.equal(observation.measurement_context.hawk_i.analysis_id, 'hawk-123');
  assert.equal(observation.measurement_context.medication_context.hours_before_assessment, 1.5);
  assert.equal(observation.effective_datetime, '2026-07-27T01:30:00.000Z');
});

test('ParkiCheck rows are idempotent for one assessment session', () => {
  const first = buildObservationRow(payload, identity, payload.assessment_session_id);
  const second = buildObservationRow(payload, identity, payload.assessment_session_id);

  assert.equal(first.fhir_id, `parkicheck-${payload.assessment_session_id}`);
  assert.equal(second.fhir_id, first.fhir_id);
});

test('mismatched assessment and activity session ids are rejected', () => {
  assert.throws(
    () => buildObservationRow(payload, identity, '44444444-4444-4444-8444-444444444444'),
    /must match/,
  );
});

test('missing optional metrics remain null instead of becoming zero', () => {
  const sparsePayload = { ...payload, n_taps: null, frequency: '' };
  const session = buildActivitySessionRow(sparsePayload, identity);

  assert.equal(session.metrics.parkicheck.n_taps, null);
  assert.equal(session.metrics.parkicheck.frequency, null);
});
