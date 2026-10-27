(function(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.ParkiCleanView = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  'use strict';
  // Presentation only: read existing event timestamps, never detect or score taps.
  function describe({ mode, type, state, taps = [], videoReady = false, now = 0, startTime = 0, durationMs = 10000 }) {
    if (type !== 'finger') return { count: null, intervalMs: null, remainingSeconds: null, status: '손가락 태핑에서 감지값을 표시합니다.' };
    const active = (mode === 'video' && videoReady) || (mode === 'updrs' && (state === 'running' || state === 'done'));
    if (!active) return { count: null, intervalMs: null, remainingSeconds: null, status: '손가락 태핑 측정 대기 · 시작 전에는 값이 표시되지 않습니다.' };
    const previous = taps.length > 1 ? taps[taps.length - 2]?.t : null;
    const latest = taps.length ? taps[taps.length - 1]?.t : null;
    const delta = Number.isFinite(previous) && Number.isFinite(latest) ? latest - previous : null;
    const intervalMs = delta !== null && delta > 0 ? Math.round(delta) : null;
    const running = mode === 'updrs' && state === 'running';
    const remainingSeconds = running && Number.isFinite(now) && Number.isFinite(startTime)
      ? Math.max(0, Math.min(durationMs, durationMs - (now - startTime))) / 1000 : null;
    return { count: taps.length, intervalMs, remainingSeconds,
      status: mode === 'video' ? '업로드 영상의 감지 기록' : state === 'done' ? '측정 종료 · 감지 기록' : '측정 중 · 감지 기록' };
  }
  return { describe };
});
