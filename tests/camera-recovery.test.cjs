const test = require('node:test');
const assert = require('node:assert/strict');
const {
  switchStream, candidateConstraints, cameraErrorMessage,
} = require('../camera-facing');

function fakeStream(mode, id, label) {
  const track = {
    label: label || '',
    stopped: false,
    stop() { this.stopped = true; },
    getSettings() { return { ...(mode ? { facingMode: mode } : {}), deviceId: id }; },
  };
  return { track, getTracks() { return [track]; }, getVideoTracks() { return [track]; } };
}
function video(stream, failFirstPlay = false) {
  return {
    srcObject: stream,
    muted: false,
    playsInline: false,
    plays: 0,
    pause() {},
    async play() {
      this.plays++;
      if (failFirstPlay && this.plays === 1) {
        const error = new Error('source changed');
        error.name = 'AbortError';
        throw error;
      }
    },
  };
}
test('Safari rear exact fails then non-exact facing retry succeeds', async () => {
  const old = fakeStream('user','front1');
  const rear = fakeStream('environment','rear1');
  const vid = video(old);
  const attempts = [];
  const result = await switchStream(
    vid,'environment','user',async request=>{
      attempts.push(request.video.facingMode);
      if (request.video.facingMode?.exact === 'environment') {
        const error = new Error('Overconstrained'); error.name='OverconstrainedError'; throw error;
      }
      return rear;
    },{sleep:async()=>{}},
  );
  assert.equal(result.ok,true);
  assert.deepEqual(attempts,[{exact:'environment'},'environment']);
  assert.equal(vid.srcObject,rear);
  assert.equal(old.track.stopped,true);
  assert.equal(vid.muted,true);
  assert.equal(vid.playsInline,true);
});

test('fallback enumerates labeled back devices after constraint failure', async () => {
  const old = fakeStream('user','front1');
  const wrong = fakeStream('user','front1','Front Camera');
  const rear = fakeStream('', 'rear2','Back Dual Camera');
  const vid = video(old);
  const used=[];
  const result = await switchStream(
    vid,'environment','user',async request=>{
      used.push(request.video);
      if(request.video.deviceId?.exact === 'rear2') return rear;
      if(request.video.facingMode?.exact === 'environment') {
        const err = new Error('Unsupported'); err.name='OverconstrainedError'; throw err;
      }
      return wrong;
    },{
      enumerateDevices:async()=>[
        {kind:'videoinput',deviceId:'front1',label:'Front Camera'},
        {kind:'videoinput',deviceId:'rear2',label:'Back Dual Camera'},
      ],
      sleep:async()=>{},
    },
  );
  assert.equal(result.ok,true);
  assert.equal(old.track.stopped,true);
  assert.equal(wrong.track.stopped,true);
  assert.equal(rear.track.stopped,false);
  assert.equal(vid.srcObject,rear);
  assert.equal(used.length,3);
  assert.equal(used[2].deviceId.exact,'rear2');
});

test('Safari abort on first playback triggers reattach once',async()=>{
  const old=fakeStream('user','front1'),rear=fakeStream('environment','rear1');
  const vid=video(old,true);
  const result=await switchStream(
    vid,'environment','user',async()=>rear,
    {sleep:async()=>{}},
  );
  assert.equal(result.ok,true);
  assert.equal(vid.srcObject,rear);
  assert.equal(vid.plays,2);
});

test('previous device cannot be presented as a successful rear switch',async()=>{
  const old=fakeStream(null,'front1','Front Camera'), wrong=fakeStream(null,'front1','');
  const fallback=fakeStream('user','front1');
  const vid=video(old);
  const result=await switchStream(
    vid,'environment','user',async constraints=>{
      if (constraints.video.facingMode?.ideal==='user')return fallback;
      return fakeStream(null,'front1','Front Camera');
    },{sleep:async()=>{}},
  );
  assert.equal(result.ok,false);
  assert.equal(result.restored,true);
  assert.equal(vid.srcObject,fallback);
  assert.equal(wrong.track.stopped,false);
});

test('returns actionable, privacy-safe camera errors without logging device IDs',()=>{
  const err=(name)=>Object.assign(new Error('detail must not be rendered'),{name});
  assert.match(cameraErrorMessage(err('NotAllowedError')),/권한/);
  assert.match(cameraErrorMessage(err('NotReadableError')),/사용 중/);
  assert.match(cameraErrorMessage(err('OverconstrainedError')),/찾을 수 없습니다/);
  assert.doesNotMatch(cameraErrorMessage(err('NotAllowedError')),/detail must not/);
  assert.equal(candidateConstraints('environment',[
    {kind:'videoinput',deviceId:'back-device',label:'Back Camera'},
    {kind:'videoinput',deviceId:'front-device',label:'Front Camera'},
  ]).length,3);
});
