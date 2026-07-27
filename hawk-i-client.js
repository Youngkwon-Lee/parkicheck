(function initHawkIClient(root, factory) {
  const client = factory();

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = client;
  }

  if (root) {
    root.HawkIClient = client;
  }
})(typeof window !== 'undefined' ? window : globalThis, function createHawkIClient() {
  const DEFAULT_BASE_URL = 'https://hawkeye-labeling-tool.vercel.app';
  const MAX_VIDEO_BYTES = 100 * 1024 * 1024;

  function normalizeMedicationContext(value) {
    if (!value || typeof value !== 'object') return null;

    const context = {
      available: value.available === true,
      source: 'patient_reported_local',
    };
    const assessmentAt = new Date(value.assessment_at);
    if (!Number.isNaN(assessmentAt.getTime())) {
      context.assessment_at = assessmentAt.toISOString();
    }

    if (!context.available) return context;

    const takenAt = new Date(value.taken_at);
    if (Number.isNaN(takenAt.getTime())) return null;
    context.taken_at = takenAt.toISOString();

    if (typeof value.medication === 'string' && value.medication.trim()) {
      context.medication = value.medication.trim().slice(0, 100);
    } else {
      context.medication = null;
    }

    const doseMg = Number(value.dose_mg);
    context.dose_mg = Number.isFinite(doseMg) && doseMg >= 0 && doseMg <= 100000
      ? doseMg
      : null;

    const hoursBeforeAssessment = Number(value.hours_before_assessment);
    context.hours_before_assessment = Number.isFinite(hoursBeforeAssessment) && hoursBeforeAssessment >= 0
      ? Number(hoursBeforeAssessment.toFixed(2))
      : null;
    return context;
  }

  function resolveAllowedPreviewBaseUrl(candidate) {
    if (!candidate) return null;
    try {
      const url = new URL(candidate);
      const isProduction = url.hostname === 'hawkeye-labeling-tool.vercel.app';
      const isTeamPreview = /^hawkeye-labeling-tool-[a-z0-9-]+-22s-projects-de7c705f\.vercel\.app$/.test(url.hostname);
      if (url.protocol !== 'https:' || (!isProduction && !isTeamPreview)) return null;
      return url.origin;
    } catch (_error) {
      return null;
    }
  }

  async function readJson(response, fallbackMessage) {
    let payload = null;

    try {
      payload = await response.json();
    } catch (_error) {
      // Preserve the HTTP status when an upstream error does not return JSON.
    }

    if (!response.ok) {
      throw new Error(payload?.error || fallbackMessage || `Hawk_I request failed (${response.status})`);
    }

    return payload;
  }

  function validateVideo(file) {
    if (!file) throw new Error('분석할 영상이 없습니다.');
    if (file.size > MAX_VIDEO_BYTES) throw new Error('Hawk_I 전송은 100MB 이하 영상만 지원합니다.');
    if (file.type && !file.type.startsWith('video/')) throw new Error('영상 파일만 Hawk_I로 전송할 수 있습니다.');
  }

  function summarizeResult(result) {
    const scoreValue = result?.updrs_score?.total_score ?? result?.updrs_score?.score;
    const score = scoreValue !== null && scoreValue !== undefined && scoreValue !== '' && Number.isFinite(Number(scoreValue))
      ? Number(scoreValue)
      : null;
    // The top-level confidence describes task classification, not score certainty.
    // Never present it as clinical-score confidence.
    const confidenceValue = result?.updrs_score?.confidence;
    const confidence = confidenceValue !== null && confidenceValue !== undefined && confidenceValue !== '' && Number.isFinite(Number(confidenceValue))
      ? Math.max(0, Math.min(1, Number(confidenceValue)))
      : null;

    return {
      score,
      confidence,
      severity: result?.updrs_score?.severity || '검토 필요',
      method: result?.updrs_score?.method || result?.scoring_method || 'Hawk_I',
      performability: result?.performability_assessment?.status || 'not_reported',
      advisoryLevel: result?.score_advisory?.level || 'review_recommended',
      advisory:
        result?.score_advisory?.summary ||
        '자동 분석 결과는 연구 보조 관측치이며 담당자의 검토가 필요합니다.',
      videoType: result?.video_type || 'finger_tapping',
    };
  }

  async function submitVideo(file, options = {}) {
    validateVideo(file);

    const fetchImpl = options.fetchImpl || fetch;
    const sleep = options.sleep || ((duration) => new Promise((resolve) => setTimeout(resolve, duration)));
    const baseUrl = (options.baseUrl || DEFAULT_BASE_URL).replace(/\/$/, '');
    const pollIntervalMs = options.pollIntervalMs ?? 1500;
    const maxPolls = options.maxPolls ?? 240;
    const onStatus = options.onStatus || (() => {});
    const signal = options.signal;
    const formData = new FormData();

    formData.append('video_file', file, file.name || 'parkicheck-video.webm');
    formData.append('test_type', 'finger_tapping');
    formData.append('scoring_method', 'coral');
    if (options.assessmentSessionId) {
      formData.append('assessment_session_id', options.assessmentSessionId);
    }
    if (options.patientId) {
      formData.append('patient_id', options.patientId);
    }
    const medicationContext = normalizeMedicationContext(options.medicationContext);
    if (medicationContext) {
      formData.append('medication_context', JSON.stringify(medicationContext));
    }

    onStatus({ phase: 'uploading' });
    const startResponse = await fetchImpl(`${baseUrl}/api/analyze`, {
      method: 'POST',
      body: formData,
      signal,
    });
    const started = await readJson(startResponse, 'Hawk_I 영상 업로드에 실패했습니다.');

    if (!started?.id) throw new Error('Hawk_I가 분석 ID를 반환하지 않았습니다.');

    onStatus({ phase: 'analyzing', id: started.id });

    for (let attempt = 0; attempt < maxPolls; attempt += 1) {
      if (signal?.aborted) throw new DOMException('Aborted', 'AbortError');

      const progressResponse = await fetchImpl(
        `${baseUrl}/api/analysis/progress/${encodeURIComponent(started.id)}`,
        { signal },
      );
      const progress = await readJson(progressResponse, 'Hawk_I 진행 상태를 확인하지 못했습니다.');

      if (progress.status === 'completed') {
        const resultResponse = await fetchImpl(
          `${baseUrl}/api/analysis/result/${encodeURIComponent(started.id)}`,
          { signal },
        );
        const result = await readJson(resultResponse, 'Hawk_I 결과를 불러오지 못했습니다.');
        onStatus({ phase: 'completed', id: started.id, result });
        return result;
      }

      if (progress.status === 'error') {
        throw new Error(progress.error || 'Hawk_I 분석이 중단되었습니다.');
      }

      onStatus({ phase: 'analyzing', id: started.id, progress });
      await sleep(pollIntervalMs);
    }

    throw new Error('Hawk_I 분석 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.');
  }

  return {
    DEFAULT_BASE_URL,
    MAX_VIDEO_BYTES,
    normalizeMedicationContext,
    resolveAllowedPreviewBaseUrl,
    submitVideo,
    summarizeResult,
    validateVideo,
  };
});
