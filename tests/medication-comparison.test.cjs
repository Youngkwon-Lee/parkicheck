const test = require('node:test');
const assert = require('node:assert/strict');

const { buildMedicationComparison } = require('../medication-comparison.js');

function result({ testedAt, score, hours, frequency, medication = '레보도파', dose = 100, type = 'finger' }) {
  return {
    tested_at: testedAt,
    score,
    frequency,
    fatigability: 8,
    factors: { test_type: type },
    medication_context: {
      available: true,
      medication,
      dose_mg: dose,
      hours_before_assessment: hours,
    },
  };
}

test('comparison requires repeated assessments under the same reported context', () => {
  const comparison = buildMedicationComparison([
    result({ testedAt: '2026-07-27T00:00:00Z', score: 2, hours: 0.5, frequency: 3.0 }),
    result({ testedAt: '2026-07-27T01:00:00Z', score: 1, hours: 1.5, frequency: 3.5, dose: 150 }),
  ]);

  assert.equal(comparison.available, false);
  assert.equal(comparison.observation_count, 1);
  assert.equal(comparison.can_infer_medication_effect, false);
});

test('comparison reports numeric deltas without claiming medication efficacy', () => {
  const comparison = buildMedicationComparison([
    result({ testedAt: '2026-07-27T00:00:00Z', score: 2, hours: 0.5, frequency: 3.0 }),
    result({ testedAt: '2026-07-28T00:00:00Z', score: 1, hours: 1.5, frequency: 3.5 }),
  ]);

  assert.equal(comparison.available, true);
  assert.equal(comparison.observation_count, 2);
  assert.deepEqual(comparison.observed_change, {
    score: -1,
    frequency: 0.5,
    fatigability: 0,
  });
  assert.equal(comparison.can_infer_medication_effect, false);
  assert.equal(comparison.requires_clinician_review, true);
});
