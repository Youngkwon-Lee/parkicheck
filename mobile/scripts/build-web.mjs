import { cpSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const mobileRoot = resolve(here, '..');
const sourceRoot = resolve(mobileRoot, '..');
const destination = join(mobileRoot, 'www');

// Explicit allowlist: never package .env, test fixtures, tokens, recordings or PHI.
const publicFiles = [
  'index.html',
  'camera-facing.js',
  'hawk-i-client.js',
  'medication-events.js',
  'medication-comparison.js',
  'assessment-session.js',
  'manifest.webmanifest',
  'service-worker.js',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/apple-touch-icon.png',
];

for (const path of publicFiles) {
  if (!existsSync(join(sourceRoot, path))) {
    throw new Error('Missing public app asset: ' + path);
  }
}
rmSync(destination, { recursive: true, force: true });
mkdirSync(destination, { recursive: true });
for (const path of publicFiles) {
  mkdirSync(resolve(destination, path, '..'), { recursive: true });
  cpSync(join(sourceRoot, path), join(destination, path));
}
console.log('Packaged ' + publicFiles.length + ' allowlisted public assets to mobile/www');
