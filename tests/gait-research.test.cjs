const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {evaluateCoverage,hawkIResultUrl}=require('../gait-research.js');
const {buildActivitySessionRow,buildObservationRow}=require('../assessment-session.js');
const id='33333333-3333-4333-8333-333333333333';
const identity={
  personId:'11111111-1111-4111-8111-111111111111',
  organizationId:'22222222-2222-4222-8222-222222222222',
};
function steps(n,duration=18000){
 return Array.from({length:n},(_,i)=>({foot:i%2?'right':'left',
  t:1000+i*duration/Math.max(1,n-1),lift:0.07}));
}
test('bilateral gait reports research coverage but no clinical score',()=>{
 const r=evaluateCoverage(steps(12),20);
 assert.equal(r.sufficient,true);
 assert.equal(r.steps,12);
 assert.match(r.reason,/임상 점수가 아닙니다/);
 assert.equal('score' in r,false);
});
test('short or poorly captured gait abstains',()=>{
 for(const data of [[],steps(4),steps(8,1000),[{foot:'left',t:1}]]){
  const r=evaluateCoverage(data,20);
  assert.equal(r.sufficient,false);
  assert.match(r.reason,/다시 촬영/);
 }
});
test('gait is stored as unscored research activity with factors',()=>{
 const row=buildActivitySessionRow({assessment_session_id:id,
  factors:{test_type:'gait',left_steps:6,right_steps:6,capture_quality:'observable'},
  score:null,mode:'live',frequency:103},identity);
 assert.equal(row.exercise_log.task_code,'GAIT_RESEARCH');
 assert.equal(row.metrics.parkicheck.score,null);
 assert.equal(row.metrics.parkicheck.factors.left_steps,6);
 assert.throws(()=>buildObservationRow({assessment_session_id:id,score:null},identity,id),/score is required/);
});
test('finger retains distinct scored activity code',()=>{
 const row=buildActivitySessionRow({assessment_session_id:id,score:1,mode:'live'},identity);
 assert.equal(row.exercise_log.task_code,'UPDRS_3_4');
});
test('dashboard link only accepts actual safe analysis identifiers',()=>{
 const key='mixkit4855_public_stock_gait_1792542221_66b73a81a38a';
 assert.equal(hawkIResultUrl(key),'https://hawkeye-labeling-tool.vercel.app/result?analysisId='+key);
 for(const value of ['',null,'short','../secret','test&x=1','a b']) assert.equal(hawkIResultUrl(value),null);
});
test('web avoids assigning MDS-UPDRS gait score and gates cross-service link',()=>{
 const html=fs.readFileSync(path.join(__dirname,'../index.html'),'utf8');
 assert.match(html,/local_scoring:'not_clinically_validated'/);
 assert.match(html,/if \(!error && !unscoredGait\)/);
 assert.match(html,/GAIT · RESEARCH OBSERVATION/);
 assert.match(html,/hawkIResultLink/);
 assert.match(html,/window.ParkiGaitResearch\?\.hawkIResultUrl/);
 assert.doesNotMatch(html,/UPDRS 3\.9 — GAIT/);
});
