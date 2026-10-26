/* ParkiCheck: only cache public, static app-shell files.
 * Auth, Supabase/third-party requests, video, recordings, and patient results
 * are never intercepted or cached here.
 */
'use strict';

const CACHE_NAME = 'parkicheck-public-shell-20261026-v2';
const CACHE_PREFIX = 'parkicheck-public-shell-';
const SHELL_PATHS = [
  '/',
  '/index.html',
  '/camera-facing.js',
  '/hawk-i-client.js',
  '/medication-events.js',
  '/medication-comparison.js',
  '/assessment-session.js',
  '/manifest.webmanifest',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(SHELL_PATHS))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
          .map((key) => caches.delete(key)),
      ))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  // Skip all query-bearing URLs, including OAuth callback codes or account-specific state.
  if (url.origin !== self.location.origin || url.search || url.hash || !SHELL_PATHS.includes(url.pathname)) return;

  if (url.pathname === '/' || url.pathname === '/index.html') {
    // Network first: never pin stale instructions/consent wording.
    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.ok && response.type === 'basic') {
            const copy = response.clone();
            event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.put(request, copy)));
          }
          return response;
        })
        .catch(() => caches.match(request)),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => cached || fetch(request)),
  );
});
