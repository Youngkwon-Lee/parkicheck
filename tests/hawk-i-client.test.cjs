const test = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeAssessmentContext,
  normalizeMedicationContext,
  resolveAllowedPreviewBaseUrl,
  resolveAllowedUploadBaseUrl,
  submitVideo,
  summarizeResult,
  validateVideo,
} = require('../hawk-i-client.js');

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

test('summarizeResult preserves the review boundary fields', () => {
  const summary = summarizeResult({
    video_type: 'finger_tapping',
    scoring_method: 'coral',
    confidence: 0.81,
    updrs_score: { score: 2, severity: 'moderate', method: 'coral', confidence: 0.81 },
    performability_assessment: { status: 'uncertain' },
    score_advisory: { level: 'review_recommended', summary: '수기 검토를 권장합니다.' },
  });

  assert.deepEqual(summary, {
    score: 2,
    confidence: 0.81,
    severity: 'moderate',
    method: 'coral',
    performability: 'uncertain',
    advisoryLevel: 'review_recommended',
    advisory: '수기 검토를 권장합니다.',
    videoType: 'finger_tapping',
  });
});

test('summarizeResult reads the Hawk I total_score contract', () => {
  const summary = summarizeResult({
    video_type: 'finger_tapping',
    updrs_score: { total_score: 3, severity: 'severe', method: 'coral', confidence: 0.72 },
  });

  assert.equal(summary.score, 3);
  assert.equal(summary.confidence, 0.72);
});

test('summarizeResult keeps a completed analysis without a score in manual review', () => {
  const summary = summarizeResult({
    success: true,
    video_type: 'finger_tapping',
    scoring_method: 'coral',
    confidence: 1,
    updrs_score: { score: null, confidence: null },
  });

  assert.equal(summary.score, null);
  assert.equal(summary.confidence, null);
  assert.equal(summary.performability, 'not_reported');
  assert.equal(summary.advisoryLevel, 'review_recommended');
  assert.match(summary.advisory, /담당자의 검토/);
});

test('submitVideo sends a consented finger task and returns the completed result', async () => {
  const calls = [];
  const statuses = [];
  const video = new File(['video'], 'finger.mp4', { type: 'video/mp4' });
  const result = { success: true, video_type: 'finger_tapping', updrs_score: { score: 1 } };
  const responses = [
    jsonResponse({ success: true, id: 'review-123', status: 'in_progress' }, 202),
    jsonResponse({ status: 'in_progress', steps: {} }),
    jsonResponse({ status: 'completed', steps: {} }),
    jsonResponse(result),
  ];

  const returned = await submitVideo(video, {
    baseUrl: 'https://hawk.example',
    uploadBaseUrl: 'https://upload.hawk.example/direct',
    assessmentSessionId: 'assessment-123',
    patientId: 'research-assessment-123',
    assessmentContext: {
      assessment_session_id: 'assessment-123',
      subject_person_id: 'person-1',
      organization_id: 'org-1',
      created_by_person_id: 'person-1',
      performer_person_id: 'person-1',
      persistence_owner: 'parkicheck',
    },
    medicationContext: {
      available: true,
      source: 'patient_reported_local',
      medication: '레보도파',
      dose_mg: 100,
      taken_at: '2026-07-27T00:00:00.000Z',
      assessment_at: '2026-07-27T01:30:00.000Z',
      hours_before_assessment: 1.5,
    },
    accessToken: 'supabase-access-token',
    fetchImpl: async (url, options = {}) => {
      calls.push({ url, options });
      return responses.shift();
    },
    pollIntervalMs: 0,
    sleep: async () => {},
    onStatus: (status) => statuses.push(status.phase),
  });

  assert.deepEqual(returned, result);
  assert.equal(calls[0].url, 'https://upload.hawk.example/direct/api/analyze');
  assert.equal(calls[1].url, 'https://hawk.example/api/analysis/progress/review-123');
  assert.equal(calls[0].options.body.get('test_type'), 'finger_tapping');
  assert.equal(calls[0].options.body.get('scoring_method'), 'coral');
  assert.equal(calls[0].options.body.get('assessment_session_id'), 'assessment-123');
  assert.equal(calls[0].options.body.get('patient_id'), 'research-assessment-123');
  assert.deepEqual(JSON.parse(calls[0].options.body.get('medication_context')), {
    available: true,
    source: 'patient_reported_local',
    assessment_at: '2026-07-27T01:30:00.000Z',
    taken_at: '2026-07-27T00:00:00.000Z',
    medication: '레보도파',
    dose_mg: 100,
    hours_before_assessment: 1.5,
  });
  assert.equal(calls[0].options.body.get('physio_contract_version'), 'parkicheck-hawk-i/v1');
  assert.equal(calls[0].options.body.get('physio_activity_session_id'), 'assessment-123');
  assert.equal(calls[0].options.body.get('physio_subject_person_id'), 'person-1');
  assert.equal(calls[0].options.body.get('physio_organization_id'), 'org-1');
  assert.equal(calls[0].options.body.get('physio_created_by_person_id'), null);
  assert.equal(calls[0].options.body.get('physio_performer_person_id'), null);
  assert.equal(calls[0].options.body.get('physio_persistence_owner'), 'parkicheck');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer supabase-access-token');
  assert.equal(calls[1].options.headers.Authorization, 'Bearer supabase-access-token');
  assert.equal(calls[3].options.headers.Authorization, 'Bearer supabase-access-token');
  assert.deepEqual(statuses, ['uploading', 'analyzing', 'analyzing', 'completed']);
});

test('submitVideo fails closed before upload when patient context has no token', async () => {
  let fetchCalled = false;
  const video = new File(['video'], 'finger.mp4', { type: 'video/mp4' });

  await assert.rejects(() => submitVideo(video, {
    assessmentSessionId: 'assessment-123',
    assessmentContext: {
      assessment_session_id: 'assessment-123',
      subject_person_id: 'person-1',
      organization_id: 'org-1',
      created_by_person_id: 'person-1',
      performer_person_id: 'person-1',
    },
    fetchImpl: async () => {
      fetchCalled = true;
      return jsonResponse({});
    },
  }), /로그인이 필요/);

  assert.equal(fetchCalled, false);
});

test('normalizeAssessmentContext rejects a mismatched cross-service session', () => {
  assert.throws(() => normalizeAssessmentContext({
    assessment_session_id: 'assessment-other',
    subject_person_id: 'person-1',
    organization_id: 'org-1',
    created_by_person_id: 'person-1',
    performer_person_id: 'person-1',
  }, 'assessment-123'), /session.*일치하지 않습니다/);
});

test('normalizeMedicationContext keeps only bounded patient-reported fields', () => {
  assert.deepEqual(normalizeMedicationContext({
    available: true,
    source: 'untrusted',
    medication: ` ${'a'.repeat(120)} `,
    dose_mg: -1,
    taken_at: '2026-07-27T00:00:00Z',
    assessment_at: '2026-07-27T01:00:00Z',
    hours_before_assessment: 1,
    secret: 'discard-me',
  }), {
    available: true,
    source: 'patient_reported_local',
    assessment_at: '2026-07-27T01:00:00.000Z',
    taken_at: '2026-07-27T00:00:00.000Z',
    medication: 'a'.repeat(100),
    dose_mg: null,
    hours_before_assessment: 1,
  });
  assert.equal(normalizeMedicationContext({ available: true, taken_at: 'invalid' }), null);
});

test('validateVideo rejects oversized input before transmission', () => {
  assert.throws(
    () => validateVideo({ size: 101 * 1024 * 1024, type: 'video/mp4' }),
    /100MB/,
  );
});

test('preview base URL accepts only the Hawk I team deployment', () => {
  assert.equal(
    resolveAllowedPreviewBaseUrl('https://hawkeye-labeling-tool-abc123-22s-projects-de7c705f.vercel.app/path'),
    'https://hawkeye-labeling-tool-abc123-22s-projects-de7c705f.vercel.app',
  );
  assert.equal(resolveAllowedPreviewBaseUrl('https://attacker.vercel.app'), null);
  assert.equal(resolveAllowedPreviewBaseUrl('http://hawkeye-labeling-tool.vercel.app'), null);
  assert.equal(
    resolveAllowedPreviewBaseUrl('https://desktop-t43sn5m-1.tailde3b80.ts.net/hawkeye-preview/'),
    'https://desktop-t43sn5m-1.tailde3b80.ts.net/hawkeye-preview',
  );
  assert.equal(resolveAllowedPreviewBaseUrl('https://desktop-t43sn5m-1.tailde3b80.ts.net/other'), null);
});

test('direct upload base accepts only the bounded Hawk I Funnel paths', () => {
  assert.equal(
    resolveAllowedUploadBaseUrl('https://desktop-t43sn5m-1.tailde3b80.ts.net/hawkeye-preview/'),
    'https://desktop-t43sn5m-1.tailde3b80.ts.net/hawkeye-preview',
  );
  assert.equal(
    resolveAllowedUploadBaseUrl('https://desktop-t43sn5m-1.tailde3b80.ts.net/hawkeye-api'),
    'https://desktop-t43sn5m-1.tailde3b80.ts.net/hawkeye-api',
  );
  assert.equal(resolveAllowedUploadBaseUrl('https://desktop-t43sn5m-1.tailde3b80.ts.net/'), null);
  assert.equal(resolveAllowedUploadBaseUrl('https://attacker.example/hawkeye-preview'), null);
  assert.equal(resolveAllowedUploadBaseUrl('http://desktop-t43sn5m-1.tailde3b80.ts.net/hawkeye-preview'), null);
});
