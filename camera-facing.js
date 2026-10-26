/* Switch an existing live camera to a requested lens without touching
 * assessment storage, recorded video, or MediaPipe model state. */
(function initCameraFacing(root, factory) {
  const value = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = value;
  if (root) root.ParkiCameraFacing = value;
})(typeof window !== 'undefined' ? window : globalThis, function buildCameraFacing() {
  function stopStream(stream) {
    if (!stream || typeof stream.getTracks !== 'function') return;
    for (const track of stream.getTracks()) track.stop();
  }

  function constraintsFor(mode) {
    if (mode !== 'user' && mode !== 'environment') throw new Error('invalid facing mode');
    return {
      audio: false,
      video: {
        // The rear lens must be real; silently returning a front-camera
        // fallback would produce misleading measurements and UI.
        facingMode: mode === 'environment' ? { exact: mode } : { ideal: mode },
        width: { ideal: 1280 },
        height: { ideal: 720 },
      },
    };
  }

  async function openCamera(video, mode, getUserMedia) {
    const stream = await getUserMedia(constraintsFor(mode));
    try {
      const track = stream.getVideoTracks && stream.getVideoTracks()[0];
      if (!track) throw new Error('no video track returned');
      const actualMode = track.getSettings && track.getSettings().facingMode;
      if (actualMode && actualMode !== mode) {
        throw new Error('requested lens is unavailable');
      }
      video.srcObject = stream;
      await video.play();
      return stream;
    } catch (error) {
      stopStream(stream);
      if (video.srcObject === stream) video.srcObject = null;
      throw error;
    }
  }

  async function switchStream(video, mode, previousMode, getUserMedia) {
    if (!video || !video.srcObject) throw new Error('camera not active');
    if (mode === previousMode) return { ok: true, mode, restored: false };
    if (typeof getUserMedia !== 'function') throw new Error('camera API unavailable');
    const priorStream = video.srcObject;
    video.pause();
    stopStream(priorStream);
    video.srcObject = null;
    try {
      await openCamera(video, mode, getUserMedia);
      return { ok: true, mode, restored: false };
    } catch (error) {
      // A failed rear-camera request must restore the current front camera.
      try {
        await openCamera(video, previousMode, getUserMedia);
        return { ok: false, mode: previousMode, restored: true, error };
      } catch (restoreError) {
        return { ok: false, mode: previousMode, restored: false, error, restoreError };
      }
    }
  }

  return { stopStream, constraintsFor, switchStream };
});
