const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const read = (name) => fs.readFileSync(path.join(root, name));
const text = (name) => read(name).toString('utf8');

test('research-only ParkiCheck PWA manifest with PNG icons', () => {
  const m = JSON.parse(text('manifest.webmanifest'));
  assert.equal(m.id, '/');
  assert.equal(m.start_url, '/');
  assert.equal(m.scope, '/');
  assert.equal(m.display, 'standalone');
  assert.equal(m.lang, 'ko');
  assert.match(m.description, /진단을 제공하지 않습니다/);
  assert.deepEqual(m.icons.map((icon) => icon.sizes), ['192x192', '512x512']);
  for (const icon of m.icons) {
    assert.match(icon.purpose, /maskable/);
    const png = read(icon.src.slice(1));
    assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert.equal(png.readUInt32BE(16), Number(icon.sizes.split('x')[0]));
    assert.equal(png.readUInt32BE(20), Number(icon.sizes.split('x')[1]));
  }
});

test('web entry registers PWA only for HTTPS browser hosts', () => {
  const html = text('index.html');
  assert.match(html, /href="\/manifest\.webmanifest"/);
  assert.match(html, /href="\/icons\/apple-touch-icon\.png"/);
  assert.match(html, /navigator\.serviceWorker\.register\('\/service-worker\.js'/);
  assert.match(html, /location\.protocol === 'https:'/);
  assert.match(html, /location\.hostname !== 'localhost'/);
  assert.match(html, /연구용 관찰 지표이며, 의학적 진단을 대신하지 않습니다/);
});

test('service worker bypasses patient APIs, remote hosts and media', () => {
  const handlers = {};
  const origin = 'https://finger-tap-fx.vercel.app';
  const fakeResponse = { ok: true, type: 'basic', clone: () => ({ ok: true }) };
  const sandbox = {
    URL,
    Promise,
    self: {
      location: { origin },
      addEventListener(name, listener) { handlers[name] = listener; },
      skipWaiting: async () => {},
      clients: { claim: async () => {} },
    },
    caches: {
      open: async () => ({ put: async () => {} }),
      match: async () => fakeResponse,
      keys: async () => [],
      delete: async () => true,
    },
    fetch: async () => fakeResponse,
  };
  vm.runInNewContext(text('service-worker.js'), sandbox);
  function intercepted(url, method = 'GET') {
    let called = false;
    handlers.fetch({
      request: { method, url },
      waitUntil() {},
      respondWith() { called = true; },
    });
    return called;
  }
  assert.equal(intercepted(origin + '/api/sessions'), false);
  assert.equal(intercepted(origin + '/api/observations'), false);
  assert.equal(intercepted(origin + '/?code=secret-login-callback'), false);
  assert.equal(intercepted(origin + '/video/patient.mp4'), false);
  assert.equal(intercepted('https://example.supabase.co/rest/v1/observations'), false);
  assert.equal(intercepted(origin + '/', 'POST'), false);
  assert.equal(intercepted(origin + '/'), true);
  assert.equal(intercepted(origin + '/hawk-i-client.js'), true);
});

test('native camera permissions present, Android local backup disabled', () => {
  const ios = text('mobile/ios/App/App/Info.plist');
  const android = text('mobile/android/app/src/main/AndroidManifest.xml');
  assert.match(ios, /<key>NSCameraUsageDescription<\/key>/);
  assert.match(ios, /별도 동의/);
  assert.match(android, /android\.permission\.CAMERA/);
  assert.match(android, /android:allowBackup="false"/);
});
