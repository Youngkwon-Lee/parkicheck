const test = require('node:test');
const assert = require('node:assert/strict');

const { createIndexTapDetector } = require('../video-tap-detector.js');

test('counts one tap for each complete open-to-contact cycle', () => {
  const detector = createIndexTapDetector();
  const samples = [
    [0.10, 0],
    [0.05, 100],
    [0.04, 167],
    [0.06, 233],
    [0.09, 300],
    [0.05, 500],
  ];

  assert.equal(samples.filter(([distance, time]) => detector.observe(distance, time)).length, 2);
});

test('does not count contact jitter until the finger clearly reopens', () => {
  const detector = createIndexTapDetector();
  const samples = [
    [0.10, 0],
    [0.05, 200],
    [0.06, 267],
    [0.05, 334],
    [0.07, 401],
    [0.05, 468],
  ];

  assert.equal(samples.filter(([distance, time]) => detector.observe(distance, time)).length, 1);
});

test('requires an open hand before counting an initial closed pose', () => {
  const detector = createIndexTapDetector();

  assert.equal(detector.observe(0.03, 0), false);
  assert.equal(detector.observe(0.10, 100), false);
  assert.equal(detector.observe(0.04, 300), true);
});

test('reset clears detector state between uploaded videos', () => {
  const detector = createIndexTapDetector();
  detector.observe(0.10, 0);
  assert.equal(detector.observe(0.04, 200), true);

  detector.reset();
  assert.equal(detector.observe(0.04, 0), false);
});
