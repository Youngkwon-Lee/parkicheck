/* ParkiCheck research gait observations, never a clinical MDS-UPDRS score. */
(function registerGaitResearch(root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.ParkiGaitResearch = api;
})(typeof window !== 'undefined' ? window : globalThis, function buildGaitResearch() {
  function evaluateCoverage(steps, durationSec) {
    const rows = Array.isArray(steps) ? steps.filter(
      v => (v.foot === 'left' || v.foot === 'right') && Number.isFinite(v.t),
    ) : [];
    const n = rows.length;
    const left = rows.filter(v => v.foot === 'left').length;
    const right = rows.filter(v => v.foot === 'right').length;
    const timeSpan = n >= 2 ? (Math.max(...rows.map(v => v.t)) - Math.min(...rows.map(v => v.t))) / 1000 : 0;
    const duration = Number.isFinite(durationSec) && durationSec > 0 ? durationSec : 0;
    // These are engineering recording-completeness checks, not clinical norms.
    const sufficient = n >= 8 && left >= 3 && right >= 3 && duration >= 10 && timeSpan >= 4;
    return {
      sufficient,
      steps: n,
      left,
      right,
      spanSeconds: Number(timeSpan.toFixed(1)),
      reason: sufficient
        ? '관찰 가능한 걸음이 양측에서 기록됐습니다. 측정값은 연구용이며 임상 점수가 아닙니다.'
        : '걸음이 충분히 추적되지 않았습니다. 양쪽 발이 모두 보이도록 다시 촬영해 주세요.',
    };
  }
  function hawkIResultUrl(value) {
    if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{8,160}$/.test(value)) return null;
    return 'https://hawkeye-labeling-tool.vercel.app/result?analysisId=' + encodeURIComponent(value);
  }
  return { evaluateCoverage, hawkIResultUrl };
});
