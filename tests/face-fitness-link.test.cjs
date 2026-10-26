const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const html=fs.readFileSync(path.resolve(__dirname,'..','index.html'),'utf8');

test('assessment chooser includes one canonical Face Fitness external link',()=>{
  const anchors=[...html.matchAll(/<a\b[^>]*id="faceFitnessRelatedApp"[^>]*>/g)];
  assert.equal(anchors.length,1);
  const el=anchors[0][0];
  assert.match(el,/href="https:\/\/face-fitness\.vercel\.app\/"/);
  assert.match(el,/target="_blank"/);
  assert.match(el,/rel="noopener noreferrer"/);
  assert.match(el,/referrerpolicy="no-referrer"/);
  assert.match(el,/aria-label="별도 Face Fitness/);
});
test('link clearly states independent research app, no data or identity transfer',()=>{
  assert.match(html,/별도 연구용 앱입니다/);
  assert.match(html,/계정 정보가 자동으로 전송되지 않습니다/);
  assert.doesNotMatch(html,/faceFitnessRelatedApp[^>]+onclick=/);
  assert.equal((html.match(/id="faceFitnessRelatedApp"/g)||[]).length,1);
});
test('link is outside clinical assessment cards and remains a dedicated anchor',()=>{
  const link=html.indexOf('id="faceFitnessRelatedApp"');
  const selector=html.indexOf('<div id="assessSelector"');
  const grid=html.indexOf('class="assess-grid"',selector);
  const back=html.indexOf('← BACK TO FREE PLAY',selector);
  const testOverlay=html.indexOf('id="updrsTestOverlay"',selector);
  assert.ok(selector>=0 && link>selector && link<grid && grid<back && back<testOverlay);
  assert.match(html,/\.related-app-link:focus-visible/);
  assert.match(html,/#assessSelector \{ overflow-y:auto;/);
});
