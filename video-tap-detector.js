(function attachVideoTapDetector(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.ParkiCheckVideoTap = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function buildVideoTapDetector() {
  function createIndexTapDetector(options = {}) {
    const closeThreshold = Number.isFinite(options.closeThreshold) ? options.closeThreshold : 0.055;
    const releaseThreshold = Number.isFinite(options.releaseThreshold) ? options.releaseThreshold : 0.085;
    const cooldownMs = Number.isFinite(options.cooldownMs) ? options.cooldownMs : 180;

    if (!(closeThreshold > 0 && releaseThreshold > closeThreshold && cooldownMs >= 0)) {
      throw new Error('Invalid video tap detector thresholds');
    }

    let armed = false;
    let lastTapMs = -Infinity;

    return {
      observe(distance, timestampMs) {
        if (!Number.isFinite(distance) || !Number.isFinite(timestampMs)) return false;

        // A clinical finger tap is an open-to-contact cycle. Requiring a wider
        // release before re-arming prevents landmark jitter near contact from
        // being counted as several taps.
        if (!armed) {
          if (distance >= releaseThreshold) armed = true;
          return false;
        }

        if (distance > closeThreshold) return false;

        armed = false;
        if (timestampMs - lastTapMs < cooldownMs) return false;
        lastTapMs = timestampMs;
        return true;
      },

      reset() {
        armed = false;
        lastTapMs = -Infinity;
      },
    };
  }

  return { createIndexTapDetector };
});
