import test from 'node:test';
import assert from 'node:assert/strict';
import { parseDevOptions, applyDevOptions, validatePort } from './dev-options.mjs';

test('portable options support separate and equals syntax', () => {
  const result = parseDevOptions(['--course', '235B', '--host=0.0.0.0', '--port', '3010']);
  assert.deepEqual({...result}, {course:'235B', host:'0.0.0.0', port:'3010'});
});
test('CLI overrides only supplied environment settings', () => {
  const env = {COURSE:'235A', HOST:'127.0.0.1', PORT:'3003'};
  applyDevOptions(parseDevOptions(['--course', '119B']), env);
  assert.deepEqual(env, {COURSE:'119B', HOST:'127.0.0.1', PORT:'3003'});
  applyDevOptions(parseDevOptions([]), env);
  assert.equal(env.COURSE, '119B');
});
test('missing values, unknown options and positional arguments fail', () => {
  for (const args of [['--course'], ['--host'], ['--port'], ['--course',''], ['--host','--port'], ['--cors'], ['235A']]) {
    assert.throws(() => parseDevOptions(args));
  }
});
test('invalid ports fail instead of silently falling back', () => {
  for (const value of ['0','65536','-1','3003.5','NaN','3e3','']) assert.throws(() => validatePort(value));
  assert.equal(validatePort('1'),1);
  assert.equal(validatePort('65535'),65535);
});
test('mobile default can be overridden and help is recognized', () => {
  assert.equal(parseDevOptions(['--host','0.0.0.0','--host','127.0.0.1']).host,'127.0.0.1');
  assert.equal(parseDevOptions(['-h']).help,true);
});
