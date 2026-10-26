/* ParkiCheck live camera switching. Never store captured data. */
(function initCameraFacing(root, factory) {
  const value = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = value;
  if (root) root.ParkiCameraFacing = value;
})(typeof window !== 'undefined' ? window : globalThis, function buildCameraFacing() {
  const DEFAULT_SETTLE_MS = 160;
  const REAR_LABEL = /\b(back|rear|environment)\b|후면/i;
  const FRONT_LABEL = /\b(front|user|facetime)\b|전면/i;

  function stopStream(stream) {
    if (!stream || typeof stream.getTracks !== 'function') return;
    for (const track of stream.getTracks()) track.stop();
  }

  function constraintsFor(mode) {
    if (mode !== 'user' && mode !== 'environment') throw new Error('invalid facing mode');
    return {
      audio: false,
      video: {
        facingMode: mode === 'environment' ? { exact: mode } : { ideal: mode },
        width: { ideal: 1280 },
        height: { ideal: 720 },
      },
    };
  }

  function candidateConstraints(mode, devices) {
    const candidates = [constraintsFor(mode), {
      audio: false, video: { facingMode: mode },
    }];
    const marker = mode === 'environment' ? REAR_LABEL : FRONT_LABEL;
    for (const device of devices || []) {
      if (device.kind === 'videoinput' && device.deviceId && marker.test(device.label || '')) {
        candidates.push({
          audio: false, video: { deviceId: { exact: device.deviceId } },
        });
      }
    }
    return candidates;
  }

  function matchesLens(track, mode, previousDeviceId, chosenConstraints) {
    const settings = track.getSettings?.() || {};
    if (settings.facingMode && settings.facingMode !== mode) return false;
    // Browsers may ignore a non-mandatory facingMode request.
    if (!settings.facingMode) {
      const marker = mode === 'environment' ? FRONT_LABEL : REAR_LABEL;
      if (marker.test(track.label || '')) return false;
    }
    // Refuse to relabel the previous physical front camera as "rear".
    if (mode === 'environment' && previousDeviceId && settings.deviceId === previousDeviceId) {
      return false;
    }
    // An explicitly selected, labeled lens is also acceptable when WebKit
    // doesn't expose MediaTrackSettings.facingMode.
    return Boolean(chosenConstraints.video);
  }

  function cameraErrorMessage(error) {
    const name = error?.name || '';
    if (name === 'NotAllowedError' || name === 'SecurityError') {
      return '카메라 권한이 거부됐습니다. Safari의 카메라 접근 설정을 확인해 주세요.';
    }
    if (name === 'NotReadableError' || name === 'AbortError') {
      return '카메라가 사용 중이거나 시작에 실패했습니다. 다른 카메라 앱을 닫고 다시 시도해 주세요.';
    }
    if (name === 'OverconstrainedError' || name === 'NotFoundError') {
      return '요청한 카메라를 찾을 수 없습니다. 사용 가능한 카메라를 확인해 주세요.';
    }
    if (name === 'NotSupportedError') {
      return '이 브라우저에서 해당 카메라를 지원하지 않습니다.';
    }
    return '카메라 전환에 실패했습니다. 다시 시도해 주세요.';
  }

  async function tryOpenCamera(video, mode, getUserMedia, options = {}) {
    let devices = [];
    if (typeof options.enumerateDevices === 'function') {
      try { devices = await options.enumerateDevices(); } catch (_) { /* optional */ }
    }
    let lastError = null;
    const candidates = candidateConstraints(mode, devices);
    for (let attempt = 0; attempt < candidates.length; attempt += 1) {
      const request = candidates[attempt];
      let stream = null;
      try {
        stream = await getUserMedia(request);
        const track = stream.getVideoTracks?.()[0];
        if (!track) throw new Error('no video track returned');
        if (!matchesLens(track, mode, options.previousDeviceId, request)) {
          const err = new Error('requested lens is unavailable');
          err.name = 'OverconstrainedError';
          throw err;
        }
        video.muted = true;
        video.playsInline = true;
        video.srcObject = stream;
        try {
          await video.play();
        } catch (error) {
          // WebKit can report an AbortError while the video source is being
          // replaced; reattach the source once before rejecting the lens.
          video.srcObject = null;
          video.srcObject = stream;
          await video.play();
        }
        return stream;
      } catch (error) {
        lastError = error;
        stopStream(stream);
        if (video.srcObject === stream) video.srcObject = null;
        if (error?.name === 'NotAllowedError' || error?.name === 'SecurityError') break;
        if (attempt < candidates.length - 1 && typeof options.sleep === 'function') {
          await options.sleep(80);
        }
      }
    }
    throw lastError || new Error('camera unavailable');
  }

  async function switchStream(video, mode, previousMode, getUserMedia, options = {}) {
    if (!video || !video.srcObject) throw new Error('camera not active');
    if (mode === previousMode) return { ok: true, mode, restored: false };
    if (typeof getUserMedia !== 'function') throw new Error('camera API unavailable');
    const previousStream = video.srcObject;
    const priorTrack = previousStream.getVideoTracks?.()[0];
    const previousDeviceId = priorTrack?.getSettings?.().deviceId || null;
    video.pause();
    stopStream(previousStream);
    video.srcObject = null;

    const sleep = options.sleep || (ms => new Promise(resolve => setTimeout(resolve, ms)));
    await sleep(DEFAULT_SETTLE_MS);
    try {
      await tryOpenCamera(video, mode, getUserMedia, {
        ...options, sleep, previousDeviceId,
      });
      return { ok: true, mode, restored: false };
    } catch (error) {
      try {
        await sleep(DEFAULT_SETTLE_MS);
        await tryOpenCamera(video, previousMode, getUserMedia, {
          ...options, sleep,
        });
        return { ok: false, mode: previousMode, restored: true, error };
      } catch (restoreError) {
        return { ok: false, mode: previousMode, restored: false, error, restoreError };
      }
    }
  }

  return { stopStream, constraintsFor, candidateConstraints, cameraErrorMessage, switchStream };
});
