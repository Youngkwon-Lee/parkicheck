const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..', '..');
const app = path.join(root, 'mobile');
const web = path.join(app, 'www');
const config = JSON.parse(fs.readFileSync(path.join(app, 'capacitor.config.json'), 'utf8'));

test('native app uses only packaged local assets', () => {
  assert.equal(config.appName, 'ParkiCheck');
  assert.equal(config.appId, 'kr.co.kinelo.parkicheck');
  assert.equal(config.webDir, 'www');
  assert.equal(config.server?.url, undefined);
  assert.ok(!JSON.stringify(config).includes('cleartext'));
});

test('native bundle contains only allowlisted, byte-identical public assets', () => {
  const expected = [
    'index.html', 'camera-facing.js', 'hawk-i-client.js', 'medication-events.js',
    'medication-comparison.js', 'assessment-session.js',
    'manifest.webmanifest', 'service-worker.js',
    'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png',
  ].sort();
  function enumerate(base, rel = '') {
    return fs.readdirSync(path.join(base, rel), { withFileTypes: true })
      .flatMap((entry) => {
        const p = path.posix.join(rel, entry.name);
        return entry.isDirectory() ? enumerate(base, p) : [p];
      });
  }
  assert.deepEqual(enumerate(web).sort(), expected);
  for (const file of expected) {
    assert.deepEqual(fs.readFileSync(path.join(web, file)), fs.readFileSync(path.join(root, file)));
  }
});
