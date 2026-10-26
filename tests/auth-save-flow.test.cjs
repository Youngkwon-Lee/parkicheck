const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
function sourceOf(name) {
  const match = html.match(new RegExp(`(?:async )?function ${name}\\([^\\n]*\\) \\{[\\s\\S]*?\\n\\}`));
  assert.ok(match, `${name} must exist in the application`);
  return match[0];
}

function createFlow({ signedIn = false, pending = true, stagedReview = false } = {}) {
  const elements = new Map();
  for (const id of ['authOverlay', 'landingOverlay', 'startOverlay', 'assessSelector', 'saveResultMsg']) {
    const classes = new Set(id === 'assessSelector' ? ['hidden'] : []);
    elements.set(id, {
      classList: { add: x => classes.add(x), remove: x => classes.delete(x), contains: x => classes.has(x) },
      textContent: '',
    });
  }
  const calls = { saves: 0, reviews: 0, analytics: [] };
  const payload = pending ? { assessment_session_id: 'synthetic-auth-flow-test' } : null;
  const context = vm.createContext({
    document: { getElementById: id => elements.get(id) },
    currentUser: signedIn ? { id: 'synthetic-user' } : null,
    lastResultPayload: payload,
    hawkIReviewPromise: null,
    pendingHawkIReview: stagedReview ? { file: 'synthetic-video', options: {} } : null,
    lastHawkIResult: null,
    switchAuthTab: () => {},
    trackAnalytics: event => calls.analytics.push(event),
    saveResultToDb: async result => { assert.equal(result, payload); calls.saves++; },
    startHawkIReview: async () => { calls.reviews++; },
    normalizedHawkIResult: result => result,
  });
  vm.runInContext(['openAuth', 'showAssessSelector', 'continueAsGuest', 'handleSaveResult'].map(sourceOf).join('\n'), context);
  return { context, elements, calls, payload };
}

for (const pending of [false, true]) {
  test(`guest return closes login without saving (pending result: ${pending})`, () => {
    const flow = createFlow({ pending, stagedReview: true });
    flow.context.continueAsGuest();
    assert.equal(flow.elements.get('authOverlay').classList.contains('hidden'), true);
    assert.equal(flow.elements.get('assessSelector').classList.contains('hidden'), false);
    assert.equal(flow.calls.saves, 0);
    assert.equal(flow.calls.reviews, 0);
    assert.equal(flow.context.lastResultPayload, flow.payload);
    assert.ok(flow.context.pendingHawkIReview, 'guest return must not discard consented staged media');
    assert.deepEqual(flow.calls.analytics, ['guest_mode_entered']);
    flow.context.continueAsGuest();
    assert.equal(flow.elements.get('authOverlay').classList.contains('hidden'), true);
  });
}

test('signed-in return resumes a pending result save', async () => {
  const flow = createFlow({ signedIn: true });
  flow.context.showAssessSelector();
  await Promise.resolve();
  assert.equal(flow.calls.saves, 1);
  assert.equal(flow.elements.get('authOverlay').classList.contains('hidden'), true);
});

test('signed-in return without a pending result does not save', () => {
  const flow = createFlow({ signedIn: true, pending: false });
  flow.context.showAssessSelector();
  assert.equal(flow.calls.saves, 0);
});

test('explicit guest save still requires login and does not upload staged media', async () => {
  const flow = createFlow({ stagedReview: true });
  flow.elements.get('authOverlay').classList.add('hidden');
  await flow.context.handleSaveResult();
  assert.equal(flow.elements.get('authOverlay').classList.contains('hidden'), false);
  assert.equal(flow.calls.saves, 0);
  assert.equal(flow.calls.reviews, 0);
  assert.equal(flow.context.lastResultPayload, flow.payload);
});

test('guest cancel then successful login resumes the same result exactly once', async () => {
  const flow = createFlow();
  await flow.context.handleSaveResult();
  flow.context.continueAsGuest();
  assert.equal(flow.elements.get('authOverlay').classList.contains('hidden'), true);
  flow.context.currentUser = { id: 'synthetic-user' };
  flow.context.showAssessSelector();
  await Promise.resolve();
  assert.equal(flow.calls.saves, 1);
  assert.equal(flow.context.lastResultPayload, flow.payload);
});
