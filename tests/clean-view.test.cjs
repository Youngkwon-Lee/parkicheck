const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { describe } = require('../clean-view');
const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(__dirname, '..', 'clean-view.css'), 'utf8');
function extract(name) {
  const start = new RegExp('^(?:async )?function '+name+'\\([^\\n]*', 'm').exec(html);
  assert.ok(start, 'Missing '+name);
  if (start[0].trim().endsWith('}')) return start[0];
  const end = html.indexOf('\n}', start.index);
  assert.notEqual(end, -1, 'Missing end '+name);
  return html.slice(start.index, end + 2);
}
function harness(clean = false) {
  const metrics = { effects: 0, painted: 0, audio: 0, suspended: 0, resumed: 0, now: 1000, shadows: [] };
  const nodes = new Map();
  const classes = new Set();
  const document = { body: { classList: { toggle(key,on) { if(on) classes.add(key); else classes.delete(key); } } },
    getElementById(id) { if(!nodes.has(id))nodes.set(id,{textContent:'',hidden:false,style:{display:'none'},attrs:{},setAttribute(k,v){this.attrs[k]=v;}});return nodes.get(id); } };
  class Effect { constructor(){metrics.effects++;} update(){} draw(){metrics.painted++;} isDead(){return false;} add(){} }
  class Audio { constructor(){metrics.audio++;this.currentTime=0;this.destination={};} suspend(){metrics.suspended++;return Promise.resolve();} resume(){metrics.resumed++;return Promise.resolve();} }
  const ctx = { clearRect(){},save(){},restore(){},beginPath(){},moveTo(){},lineTo(){},stroke(){},arc(){},fill(){},
    createRadialGradient(){throw new Error('Clean hand must not create glow gradients');} };
  Object.defineProperty(ctx,'shadowBlur',{set(value){metrics.shadows.push(value);}});
  const sandbox={document,ParkiCleanView:{describe},window:{AudioContext:Audio,webkitAudioContext:Audio},
    Date:{now:()=>metrics.now},Math,Number,Boolean,String,console,ctx,
    Particle:Effect,Shockwave:Effect,GlowPulse:Effect,RingSegment:Effect,Burst:Effect,BgWave:Effect,ScreenFlash:Effect,FingerTrail:Effect,
    requestAnimationFrame(){},updateFreeHUD(){},updateTimerRing(){},drawLiveGraph(){},
    getLiveCameraViewport(){return{x:0,y:0,width:800,height:600};},projectLiveCameraLandmark(lm){return{x:lm.x*800,y:lm.y*600};}};
  vm.createContext(sandbox);
  vm.runInContext(`
    const THUMB_TIP=4,FINGER_TIPS=[8,12,16,20],FINGER_COLORS=['#00ffcc','#ff00ff','#ffff00','#ff6600'],FINGER_FREQS=[523,659,784,1047];
    const TAP_THRESH=0.065,TAP_COOLDOWN=140,COMBO_WINDOW=1300,ARREST_THRESHOLD=600;
    const clamp=(v,lo=0,hi=4)=>Math.max(lo,Math.min(hi,v));
    const FACTOR_WEIGHTS = {freq:0.35, arrest:0.25, rhythm:0.15, amp:0.15, fatig:0.10};
    const TEST_DURATIONS={finger:10000};
    const CONNECTIONS=[[0,1],[1,2],[2,3],[3,4],[0,5],[5,6],[6,7],[7,8],[0,17]];
    var cleanViewEnabled=${clean},cleanVideoReadoutReady=false,effects=[],bgWaves=[],trails={},prevTap={},lastTapMs={};
    var tapCount=0,combo=0,lastTapTime=0,tapHistory=[],audioCtx=null,cameraStarted=false;
    var appMode='updrs',testState='running',testType='finger',graphPulse=0,cameraFacingMode='user';
    var testData={taps:[],startTime:1000,arrests:0,lastTapT:1000,currentMaxDist:0,handSizeRef:0};
    var canvas={width:800,height:600},video={style:{}},videoEl={currentTime:0},vLB={x:0,y:0,w:800,h:600};
    var handResults=null,poseResults=null,faceMeshResults=null;
    const quietTrail={add(){},draw(){}};
    ${['initAudio','playTap','getTrail','triggerTap','detectTaps','detectTapsVideo','scoreUPDRS','updateCleanReadout','setCleanView','drawFingerTapCharge','drawHand','frame'].map(extract).join('\n')}
  `,sandbox);
  return { sandbox,metrics,nodes,classes,run:code=>vm.runInContext(code,sandbox),json:code=>JSON.parse(vm.runInContext('JSON.stringify('+code+')',sandbox)) };
}
function hand(closed) { const lm=Array.from({length:21},()=>({x:.9,y:.9}));lm[0]={x:.4,y:.15};lm[9]={x:.4,y:.45};lm[4]={x:.4,y:.4};lm[8]={x:closed?.43:.7,y:.4};return lm; }
function sequence(clean,video=false) {
  const h=harness(clean);if(video)h.run("appMode='video';cleanVideoReadoutReady=true");
  for(let i=0;i<10;i++){h.metrics.now=1000+i*200;h.sandbox.sample=hand(i%2===1);h.sandbox.ts=h.metrics.now;h.run(video?'detectTapsVideo(sample,0,ts)':'detectTaps(sample,0)');}
  return { h,result:h.json('({data:testData,count:tapCount,history:tapHistory,score:scoreUPDRS(testData.taps,testData.arrests,10)})') };
}
test('clean metrics are idle-safe and do not expose an earlier measurement in FREE',()=>{
  assert.equal(describe({mode:'free',type:'finger',state:'idle',taps:[{t:1},{t:501}]}).count,null);
  assert.equal(describe({mode:'updrs',type:'finger',state:'idle',taps:[{t:1},{t:501}]}).intervalMs,null);
  assert.equal(describe({mode:'updrs',type:'hand',state:'running',taps:[{t:1}]}).count,null);
});
test('clean metrics show detected count and latest interval, not a clinical score',()=>{
  const taps=Object.freeze([Object.freeze({t:1000}),Object.freeze({t:1321.4}),Object.freeze({t:1710})]);
  const view=describe({mode:'updrs',type:'finger',state:'running',taps,now:3500,startTime:1000});
  assert.deepEqual(view,{count:3,intervalMs:389,remainingSeconds:7.5,status:'측정 중 · 감지 기록'});
  assert.equal('score' in view,false);assert.equal(taps[2].t,1710);
});
test('one tap or invalid intervals never invent a timing value',()=>{
  for(const taps of [[{t:10}],[{t:10},{t:10}],[{t:20},{t:10}],[{t:10},{t:NaN}]])assert.equal(describe({mode:'video',videoReady:true,type:'finger',taps}).intervalMs,null);
});
test('video timestamps use their own time base, independent of wall clock',()=>{
  const v=describe({mode:'video',videoReady:true,type:'finger',state:'idle',taps:[{t:0},{t:400}],now:999999999});
  assert.equal(v.intervalMs,400);assert.equal(v.remainingSeconds,null);assert.equal(v.count,2);
});
test('remaining time is bounded and completed tests retain their real records',()=>{
  assert.equal(describe({mode:'updrs',type:'finger',state:'running',now:100000,startTime:0}).remainingSeconds,0);
  assert.equal(describe({mode:'updrs',type:'finger',state:'running',now:0,startTime:1000}).remainingSeconds,10);
  assert.equal(describe({mode:'updrs',type:'finger',state:'done',taps:[{t:10}]}).count,1);
});
test('live detection stores and scores exactly the same synthetic contacts in both views',()=>{
  const normal=sequence(false),clean=sequence(true);assert.equal(clean.result.data.taps.length,5);assert.deepEqual(clean.result,normal.result);
  assert.ok(normal.h.metrics.effects>0);assert.equal(clean.h.metrics.effects,0);
});
test('uploaded-video detection stores and scores the same contacts with no clean effects',()=>{
  const normal=sequence(false,true),clean=sequence(true,true);assert.equal(clean.result.data.taps.length,5);assert.deepEqual(clean.result,normal.result);
  assert.ok(normal.h.metrics.effects>0);assert.equal(clean.h.metrics.effects,0);
});
test('clean toggle clears only presentation queues, never recording state or tap history',()=>{
  const h=sequence(false).h;const before=h.json('({testData,prevTap,lastTapMs,tapCount,tapHistory,testState,appMode})');h.run('setCleanView(true)');
  assert.deepEqual(h.json('({testData,prevTap,lastTapMs,tapCount,tapHistory,testState,appMode})'),before);
  assert.equal(h.run('effects.length+bgWaves.length+Object.keys(trails).length'),0);
  assert.equal(h.nodes.get('cleanViewToggle').attrs['aria-pressed'],'true');assert.ok(h.classes.has('clean-view'));
  assert.equal(h.metrics.audio,0);assert.equal(h.nodes.get('cleanViewCount').textContent,'5');
  h.run('setCleanView(false)');assert.equal(h.nodes.get('cleanViewPanel').hidden,true);assert.equal(h.metrics.audio,0);
});
test('clean view never initializes audio or oscillators; exiting after camera start restores audio',()=>{
  const h=harness(true);h.run('initAudio(); playTap(440,3)');assert.equal(h.metrics.audio,0);
  h.run('cameraStarted=true;setCleanView(false)');assert.equal(h.metrics.audio,1);assert.equal(h.metrics.resumed,1);
  h.run('setCleanView(true);playTap(440,3)');assert.equal(h.metrics.audio,1);assert.equal(h.metrics.suspended,1);
});
test('clean live renderer does not draw queued particles, waves or trails',()=>{
  const h=harness(true);h.run('effects=[new Particle()];bgWaves=[new BgWave()];trails.a=new FingerTrail();frame()');
  assert.equal(h.metrics.painted,0);assert.equal(h.run('effects.length+bgWaves.length'),0);
});
test('clean hand keeps landmark geometry but never draws charge gradients or shadow glow',()=>{
  const h=harness(true);h.sandbox.sample=hand(true);h.run('drawHand(sample,[true,false,false,false])');
  assert.ok(h.metrics.shadows.length>0);assert.ok(h.metrics.shadows.every(v=>v===0));
});
test('both renderers gate effects while the new readout is display-only',()=>{
  const live=extract('frame'),upload=extract('analyzeVideoFile');
  for(const source of [live,upload]){assert.match(source,/if \(!cleanViewEnabled\) \{\s*const flashes/);assert.match(source,/updateCleanReadout\(\)/);}
  const toggle=extract('setCleanView');assert.doesNotMatch(toggle,/getUserMedia|camera\.start|startTest|setMode\(|handleSaveResult|\.from\(|testData\s*=/);
  assert.doesNotMatch(extract('updateCleanReadout'),/testData\.\w+\s*=|scoreUPDRS|saveResult|\.push\(/);
});
test('clean control is opt-in, accessible, does not hide video and keeps mobile readout in bounds',()=>{
  assert.match(html,/let cleanViewEnabled = false/);assert.match(html,/id="cleanViewToggle" aria-pressed="false" aria-controls="cleanViewPanel"/);
  assert.match(html,/id="cleanViewPanel"[^>]* hidden/);assert.match(html,/role="status" aria-live="polite"/);
  assert.match(css,/#cleanViewToggle:focus-visible/);assert.match(css,/width:calc\(100% - 24px\)/);assert.doesNotMatch(css,/#video[^{}]*\{[^}]*display\s*:\s*none/);
  assert.match(html,/최근 감지 간격/);assert.match(html,/진단이나 임상 정확도 검증이 아닙니다/);
});

test('entering VIDEO never labels previous live taps as uploaded detections',()=>{
  const v=describe({mode:'video',type:'finger',state:'idle',taps:[{t:1000},{t:1400}],videoReady:false});
  assert.equal(v.count,null);assert.equal(v.intervalMs,null);
  assert.match(extract('setMode'),/cleanVideoReadoutReady = false;\s*appMode = mode/);
  assert.match(extract('analyzeVideoFile'),/cleanVideoReadoutReady = false/);
});
test('clean renderer keeps non-finger detection but suppresses decorative pose, face and scope drawing',()=>{
  const h=harness(true);let detected=0;h.sandbox.detectGait=()=>detected++;h.sandbox.drawPoseSkeleton=()=>{throw new Error('pose overlay not clean')};
  h.run("testType='gait';poseResults={poseLandmarks:[]};frame()");assert.equal(detected,1);
  h.sandbox.detectFace=()=>detected++;h.sandbox.drawFaceMesh=()=>{throw new Error('face overlay not clean')};
  h.run("testType='face';faceMeshResults={multiFaceLandmarks:[[]]};frame()");assert.equal(detected,2);
  h.sandbox.drawTremorScope=()=>{throw new Error('scope not clean')};h.run("testType='tremor';frame()");
});

test('review branch disables only its own automatic Vercel deployment, not CI or production',()=>{
  const config=JSON.parse(fs.readFileSync(path.join(__dirname,'..','vercel.json'),'utf8'));
  assert.deepEqual(config.git.deploymentEnabled,{'aside/parkicheck-clean-view-20261027':false});
  assert.deepEqual(Object.keys(config).sort(),['$schema','git']);
});
