(function initParkiAssessmentSession(root, factory) {
  const session = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = session;
  if (root) root.ParkiAssessmentSession = session;
})(typeof window !== 'undefined' ? window : globalThis, function createParkiAssessmentSession() {
  const TIMELINE_CONTRACT_VERSION = 'parkicheck-hawk-i/v1';

  function requiredText(value, label) {
    if (typeof value !== 'string' || !value.trim()) throw new Error(`${label} is required`);
    return value.trim();
  }

  function assessmentTimestamp(payload) {
    const candidate = payload?.medication_context?.assessment_at;
    const parsed = candidate ? new Date(candidate) : new Date();
    return Number.isNaN(parsed.getTime()) ? new Date().toISOString() : parsed.toISOString();
  }

  function finiteNumber(value) {
    if (value === null || value === undefined || value === '') return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  function buildAssessmentContext(payload, identity) {
    const assessmentSessionId = requiredText(payload?.assessment_session_id, 'assessment_session_id');
    const personId = requiredText(identity?.personId, 'person_id');
    const organizationId = requiredText(identity?.organizationId, 'organization_id');
    const createdBy = requiredText(identity?.createdBy || personId, 'created_by');
    const performerPersonId = requiredText(identity?.performerPersonId || personId, 'performer_person_id');

    return {
      contract_version: 'parkicheck-hawk-i/v1',
      assessment_session_id: assessmentSessionId,
      subject_person_id: personId,
      organization_id: organizationId,
      created_by_person_id: createdBy,
      performer_person_id: performerPersonId,
      persistence_owner: 'parkicheck',
      medication_context: payload?.medication_context || null,
    };
  }

  function buildActivitySessionRow(payload, identity, options = {}) {
    const context = buildAssessmentContext(payload, identity);
    const assessmentSessionId = context.assessment_session_id;
    const personId = context.subject_person_id;
    const organizationId = context.organization_id;
    const createdBy = context.created_by_person_id;
    const duration = finiteNumber(payload?.duration_sec);

    const status = options.status || 'completed';
    if (!['planned', 'in_progress', 'completed', 'cancelled', 'skipped'].includes(status)) {
      throw new Error('invalid activity session status');
    }

    const row = {
      id: assessmentSessionId,
      subject_person_id: personId,
      organization_id: organizationId,
      created_by: createdBy,
      activity_type: 'assessment',
      source: 'camera',
      status,
      performed_at: assessmentTimestamp(payload),
      metrics: {
        contract_version: TIMELINE_CONTRACT_VERSION,
        app_source: 'parkicheck',
        assessment_session_id: assessmentSessionId,
        integration_context: context,
        medication_context: payload?.medication_context || null,
        parkicheck: {
          score: finiteNumber(payload?.score),
          raw_score: finiteNumber(payload?.raw_score),
          frequency: finiteNumber(payload?.frequency),
          fatigability: finiteNumber(payload?.fatigability),
          confidence: payload?.confidence || null,
          mode: payload?.mode || null,
          n_taps: finiteNumber(payload?.n_taps),
        },
        hawk_i: payload?.hawk_i || null,
      },
      exercise_log: {
        task_code: 'UPDRS_3_4',
        task_display: 'UPDRS Part III Item 3.4 - Finger Tapping',
        hawk_i_analysis_id: payload?.hawk_i?.analysis_id || null,
      },
      notes: 'ParkiCheck finger-tapping assessment with optional Hawk I research review',
    };
    if (duration !== null && duration >= 0) row.duration_seconds = Math.round(duration);
    return row;
  }

  function buildObservationRow(payload, identity, activitySessionId) {
    const context = buildAssessmentContext(payload, identity);
    const assessmentSessionId = context.assessment_session_id;
    const sessionId = requiredText(activitySessionId, 'activity_session_id');
    if (assessmentSessionId !== sessionId) throw new Error('assessment and activity session ids must match');
    const personId = context.subject_person_id;
    const organizationId = context.organization_id;
    const createdBy = context.created_by_person_id;
    const score = finiteNumber(payload?.score);
    if (score === null) throw new Error('score is required');

    return {
      fhir_id: `parkicheck-${assessmentSessionId}`,
      subject_person_id: personId,
      organization_id: organizationId,
      created_by: createdBy,
      performer_person_id: context.performer_person_id,
      activity_session_id: sessionId,
      status: 'final',
      source_type: 'device',
      code: 'UPDRS_3_4',
      code_system: 'http://www.nih.gov/updrs',
      code_display: 'UPDRS Part III Item 3.4 - Finger Tapping',
      category: ['motor-assessment', 'neurological', 'parkicheck'],
      value_type: 'integer',
      value_integer: Math.round(score),
      measurement_context: {
        contract_version: TIMELINE_CONTRACT_VERSION,
        app_source: 'parkicheck',
        assessment_session_id: assessmentSessionId,
        integration_context: context,
        medication_context: payload?.medication_context || null,
        hawk_i: payload?.hawk_i || null,
        frequency: finiteNumber(payload?.frequency),
        amplitude: finiteNumber(payload?.max_amplitude),
        arrests: finiteNumber(payload?.arrests),
        iti_cv: finiteNumber(payload?.iti_cv),
        fatigability: finiteNumber(payload?.fatigability),
        confidence: payload?.confidence || null,
        mode: payload?.mode || null,
        n_taps: finiteNumber(payload?.n_taps),
        duration_sec: finiteNumber(payload?.duration_sec),
        factors: payload?.factors || null,
      },
      effective_datetime: assessmentTimestamp(payload),
    };
  }

  return {
    TIMELINE_CONTRACT_VERSION,
    assessmentTimestamp,
    buildAssessmentContext,
    buildActivitySessionRow,
    buildObservationRow,
  };
});
