(function initParkiMedicationComparison(root, factory) {
  const comparison = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = comparison;
  if (root) root.ParkiMedicationComparison = comparison;
})(typeof window !== 'undefined' ? window : globalThis, function createMedicationComparison() {
  function medicationContextFor(result) {
    return result?.medication_context
      || result?.factors?.integration?.medication_context
      || null;
  }

  function asFinite(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  function buildMedicationComparison(results, testType = null) {
    const observations = (Array.isArray(results) ? results : [])
      .map((result) => {
        const context = medicationContextFor(result);
        const score = asFinite(result?.score);
        const testedAt = new Date(result?.tested_at);
        if (!context?.available || score === null || Number.isNaN(testedAt.getTime())) return null;
        const resolvedType = result?.factors?.test_type || 'finger';
        if (testType && resolvedType !== testType) return null;
        return {
          tested_at: testedAt.toISOString(),
          test_type: resolvedType,
          medication: context.medication || '약물명 미입력',
          dose_mg: asFinite(context.dose_mg),
          hours_after_reported_dose: asFinite(context.hours_before_assessment),
          score,
          frequency: asFinite(result?.frequency),
          fatigability: asFinite(result?.fatigability),
        };
      })
      .filter(Boolean);

    const groups = new Map();
    observations.forEach((observation) => {
      const key = [observation.test_type, observation.medication, observation.dose_mg ?? ''].join('|');
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(observation);
    });
    const candidates = [...groups.values()]
      .map((group) => group.sort((a, b) => new Date(a.tested_at) - new Date(b.tested_at)))
      .sort((a, b) => {
        if (b.length !== a.length) return b.length - a.length;
        return new Date(b[b.length - 1].tested_at) - new Date(a[a.length - 1].tested_at);
      });
    const selected = candidates[0] || [];

    if (selected.length < 2) {
      return {
        available: false,
        observation_count: selected.length,
        reason: 'needs_repeated_comparable_assessments',
        can_infer_medication_effect: false,
      };
    }

    const first = selected[0];
    const latest = selected[selected.length - 1];
    const delta = (left, right) => left === null || right === null
      ? null
      : Number((right - left).toFixed(2));
    return {
      available: true,
      observation_count: selected.length,
      test_type: latest.test_type,
      medication: latest.medication,
      dose_mg: latest.dose_mg,
      first,
      latest,
      observed_change: {
        score: delta(first.score, latest.score),
        frequency: delta(first.frequency, latest.frequency),
        fatigability: delta(first.fatigability, latest.fatigability),
      },
      evidence_level: 'observational_repeated_assessments',
      can_infer_medication_effect: false,
      requires_clinician_review: true,
    };
  }

  return { buildMedicationComparison, medicationContextFor };
});
