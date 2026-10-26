const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { stopStream, constraintsFor, switchStream } = require('../camera-facing.js');

function stream(mode, options = {}) {
  const track = {
    stopped: false,
    stop() { this.stopped = true; },
    getSettings: () => options.noSetting ? {} : { facingMode: mode },
  };
  return { track, getTracks: () => [track], getVideoTracks: () => options.noVideo ? [] : [track] };
}
function videoWith(live) {
  return {
    srcObject: live,
    pauses: 0,
    plays: 0,
    pause() { this.pauses++; },
    async play() { this.plays++; },
  };
}
test('rear is exact while front is best-effort for desktops', () => {
  const rear = constraintsFor('environment');
  const front = constraintsFor('user');
  assert.deepEqual(rear.video.facingMode, { exact: 'environment' });
  assert.deepEqual(front.video.facingMode, { ideal: 'user' });
  assert.equal(rear.audio, false);
  assert.throws(() => constraintsFor('left'), /invalid facing mode/);
});
test('front-to-rear switches video stream, stopping old front', async () => {
  const front = stream('user');
  const back = stream('environment');
  const video = videoWith(front);
  const asked = [];
  const result = await switchStream(video, 'environment', 'user', async constraints => {
    asked.push(constraints);
    return back;
  });
  assert.deepEqual(result, { ok: true, mode: 'environment', restored: false });
  assert.equal(video.srcObject, back);
  assert.equal(front.track.stopped, true);
  assert.equal(back.track.stopped, false);
  assert.equal(video.plays, 1);
  assert.deepEqual(asked[0].video.facingMode, { exact: 'environment' });
});
test('unavailable rear restores original front without mislabeling', async () => {
  const front = stream('user');
  const restored = stream('user');
  const video = videoWith(front);
  const asked = [];
  const result = await switchStream(video, 'environment', 'user', async constraints => {
    asked.push(constraints.video.facingMode);
    if (constraints.video.facingMode?.exact === 'environment') {
      const error = new Error('No matching rear camera');
      error.name = 'NotFoundError';
      throw error;
    }
    return constraints.video.facingMode === 'environment' ? stream('user') : restored;
  }, { sleep: async () => {} });
  assert.equal(result.ok, false);
  assert.equal(result.mode, 'user');
  assert.equal(result.restored, true);
  assert.equal(video.srcObject, restored);
  assert.equal(front.track.stopped, true);
  assert.equal(restored.track.stopped, false);
  assert.deepEqual(asked, [{ exact: 'environment' }, 'environment', { ideal: 'user' }]);
});
test('incorrectly returned lens is rejected and front restored', async () => {
  const front = stream('user'), wrong = stream('user'), restored = stream('user');
  const video = videoWith(front);
  let calls = 0;
  const result = await switchStream(video,'environment','user', async ()=>{
    calls++;
    return calls === 1 ? wrong : restored;
  });
  assert.equal(result.ok,false);
  assert.equal(result.restored,true);
  assert.equal(wrong.track.stopped,true);
  assert.equal(video.srcObject,restored);
});
test('if restoration also fails, stream remains stopped and error returned', async () => {
  const prior = stream('user');
  const video = videoWith(prior);
  const result = await switchStream(video, 'environment', 'user', async () => {
    throw new Error('NotAllowedError');
  });
  assert.equal(result.ok,false);
  assert.equal(result.restored,false);
  assert.equal(video.srcObject,null);
  assert.equal(prior.track.stopped,true);
});
test('inactive camera cannot be switched; same-mode is harmless', async () => {
  await assert.rejects(switchStream(videoWith(null),'environment','user',async ()=>{}), /camera not active/);
  const current = stream('user');
  const video = videoWith(current);
  const same = await switchStream(video,'user','user',async ()=>{throw Error('should not call');});
  assert.equal(same.ok,true);
  assert.equal(video.srcObject,current);
  assert.equal(current.track.stopped,false);
  stopStream(current);
  assert.equal(current.track.stopped,true);
});
test('integration: rear is not mirrored, uploaded videos remain unmirrored', () => {
  const html = fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
  assert.match(html, /id="video"\s+autoplay\s+muted\s+playsinline/);
  assert.match(html, /#video\[data-facing-mode="environment"\]\s*\{\s*transform:none/);
  assert.match(html, /mirror = opts\.mirror \?\? \(cameraFacingMode === "user"\)/);
  assert.match(html, /projectLiveCameraPoint\(x, y, mirror = \(cameraFacingMode === "user"\)\)/);
  assert.match(html, /mirror:false/);
  assert.equal((html.match(/data-camera-toggle(?=[ >])/g) || []).length,2);
  assert.match(html, /testState !== 'idle'/);
  assert.match(html, /liveHawkIRecordingEnabled/);
  assert.match(html, /await window\.ParkiCameraFacing\.switchStream/);
  assert.match(html, /document\.querySelectorAll\('\[data-camera-toggle\]'\)/);
});
